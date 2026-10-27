import Foundation
import linphonesw
import AVFoundation

#if IOSPHONELIB_PRIVATE
import iOSPhoneLib_Private
#else
import LinphoneWrapper
#endif

public typealias RegistrationCallback = (RegistrationState) -> Void

class LinphoneManager: LinphoneLoggingServiceDelegate {

    private(set) var config: VoIPLibConfig?
    var isInitialized: Bool {
        linphoneCore != nil
    }
    
    internal var linphoneCore: Core!
    private lazy var linphoneListener = { LinphoneListener(manager: self) }()
    private lazy var registrationListener = { LinphoneRegistrationListener(manager: self) }()
    internal lazy var linphoneAudio = { LinphoneAudio(manager: self) }()
    
    var isMicrophoneMuted: Bool {
        return !linphoneCore.micEnabled
    }
    
    /**
     * We're going to store the auth object that we used to authenticate with successfully, so we
     * know we need to re-register if it has changed.
     */
    private var lastRegisteredCredentials: Auth? = nil

    /**
     * The amount of time to wait for the server to answer an un-REGISTER, e.g. when there is no
     * network.
     */
    private let unregisterTimeoutSecs: Double = 5

    private var unregisteringAccount: Account? = nil

    private var unregisterCompletion: (() -> Void)? = nil

    private var unregisterTimeout: DispatchWorkItem? = nil
    
    var pil: PIL {
        return PIL.shared!
    }
    
    init() {
        registrationListener = LinphoneRegistrationListener(manager: self)
        linphoneListener = LinphoneListener(manager: self)
    }
    
    func initialize(config: VoIPLibConfig) -> Bool {
        self.config = config

        if isInitialized {
            log("Linphone already init")
            return true
        }

        do {
            try startLinphone()
            return true
        } catch {
            log("Failed to start Linphone \(error.localizedDescription)")
            linphoneCore = nil
            return false
        }
    }
    
    private func startLinphone() throws {
        LoggingService.Instance.logLevel = .Debug
        linphoneCore = try Factory.Instance.createCore(configPath: "", factoryConfigPath: "", systemContext: nil)
        linphoneCore.addDelegate(delegate: linphoneListener)
        try applyPreStartConfiguration(core: linphoneCore)
        try linphoneCore.start()
        applyPostStartConfiguration(core: linphoneCore)
        configureCodecs(core: linphoneCore)
    }

    private func applyPreStartConfiguration(core: Core) throws {
        if let transports = core.transports {
            transports.tlsPort = 0
            transports.udpPort = 0
            transports.tcpPort = 0
        }
        core.setUserAgent(name: pil.app.userAgent, version: nil)
        core.ringback = ringbackPath        
        core.pushNotificationEnabled = false
        core.callkitEnabled = true
        core.ipv6Enabled = false
        core.dnsSrvEnabled = false
        core.dnsSearchEnabled = false
        core.maxCalls = 2
        core.uploadBandwidth = 0
        core.downloadBandwidth = 0
        core.mtu = 1300
        core.guessHostname = true
        core.incTimeout = 60
        core.audioPort = -1
        core.nortpTimeout = 30
        core.avpfMode = AVPFMode.Disabled
        core.audioJittcomp = 100
        
        if let transports = linphoneCore.transports {
            transports.tlsPort = -1
            transports.udpPort = 0
            transports.tcpPort = 0
            try linphoneCore.setTransports(newValue: transports)
        }

        try linphoneCore.setMediaencryption(newValue: MediaEncryption.SRTP)
        linphoneCore.mediaEncryptionMandatory = true
    }
    
    func applyPostStartConfiguration(core: Core) {
        core.useInfoForDtmf = true
        core.useRfc2833ForDtmf = true
        core.adaptiveRateControlEnabled = true

        if core.hasBuiltinEchoCanceller() {
            core.echoCancellationEnabled = false
            log("Built-in echo cancellation detected, disabling software.")
        } else {
            core.echoCancellationEnabled = true
            log("This device does not have built-in echo cancellation, enabled software.")
        }
    }
    
    internal var registrationCallbacks: [RegistrationCallback] = []
    
    func register(callback: @escaping RegistrationCallback) {
        do {
            guard let auth = pil.auth else {
                throw InitializationError.noConfigurationProvided
            }
            
            if lastRegisteredCredentials != auth && lastRegisteredCredentials != nil {
                log("Auth appears to have changed, unregistering old.")
                unregister()
            }

            linphoneCore.removeDelegate(delegate: self.registrationListener)
            linphoneCore.addDelegate(delegate: self.registrationListener)

            self.registrationCallbacks.append(callback)

            if (!linphoneCore.accountList.isEmpty) {
                log("We are already registered, refreshing registration.")
                linphoneCore.refreshRegisters()
                return
            }
            
            log("No valid registrations, registering for the first time.")

            let account = try createAccount(core: linphoneCore, auth: auth)
            try linphoneCore.addAccount(account: account)
            try linphoneCore.addAuthInfo(info: createAuthInfo(auth: auth))
            linphoneCore.defaultAccount = account
        } catch (let error) {
            log("Linphone registration failed: \(error)")
            callback(.failed)
        }
    }

    private func createAuthInfo(auth: Auth) throws -> AuthInfo {
        return try Factory.Instance.createAuthInfo(
            username: auth.username,
            userid: auth.username,
            passwd: auth.password,
            ha1: "",
            realm: "",
            domain: auth.domain
        )
    }

    private func createAccount(core: Core, auth: Auth) throws -> Account {
        let params = try core.createAccountParams()
        
        let identityUrl = "sip:\(auth.username)@\(auth.domain):\(auth.port)"
        guard let identityAddress = core.interpretUrl(url: identityUrl, applyInternationalPrefix: false) else {
            log("Unable to create account, failed to interpret identity URL: \(identityUrl)", level: .error)
            throw InitializationError.noConfigurationProvided
            }
        try params.setIdentityaddress(newValue: identityAddress)
        
        params.registerEnabled = true
        
        let serverUrl = "sip:\(auth.domain);transport=tls"
        guard let serverAddress = core.interpretUrl(url: serverUrl, applyInternationalPrefix: false) else {
            log("Unable to create account, failed to interpret server URL: \(serverUrl)", level: .error)
            throw InitializationError.noConfigurationProvided
        }
        try params.setServeraddress(newValue: serverAddress)
        
        return try linphoneCore.createAccount(params: params)
    }
    
    func unregister() {
        linphoneCore.clearAccounts()
        linphoneCore.clearAllAuthInfo()
        log("Unregister complete")
    }

    func unregisterAndWait(completion: @escaping () -> Void) {
        if let previous = unregisterCompletion {
            unregisterCompletion = { previous(); completion() }
            return
        }

        guard let core = linphoneCore, let account = core.defaultAccount, let params = account.params?.clone() else {
            log("Nothing to unregister.")
            completion()
            return
        }

        unregisteringAccount = account
        unregisterCompletion = completion

        let timeout = DispatchWorkItem { [weak self] in
            self?.finishUnregister(outcome: "timed out", isError: true)
        }
        unregisterTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + unregisterTimeoutSecs, execute: timeout)

        log("Unregistering account.")
        params.registerEnabled = false
        account.params = params
    }

    /// Returns true when the state change belonged to a pending unregister, so it must not be
    /// treated as a registration update.
    func handleUnregisterStateChange(account: Account, state: LinphoneRegistrationState, message: String) -> Bool {
        guard account === unregisteringAccount else { return false }

        switch state {
        case .Cleared: finishUnregister(outcome: "cleared")
        case .Failed: finishUnregister(outcome: "failed: \(message)", isError: true)
        default: break
        }

        return true
    }

    private func finishUnregister(outcome: String, isError: Bool = false) {
        guard let completion = unregisterCompletion else { return }
        unregisterCompletion = nil
        unregisteringAccount = nil
        unregisterTimeout?.cancel()
        unregisterTimeout = nil

        log("Unregister \(outcome)", level: isError ? .error : .info)
        completion()
    }

    func terminateAllCalls() {
        do {
           try linphoneCore.terminateAllCalls()
        } catch {
            
        }
    }
    
    func call(to number: String) -> VoIPLibCall? {
        let url = "\(number)@\(pil.auth!.domain)"
        
        guard let address = linphoneCore.interpretUrl(url: url, applyInternationalPrefix: false) else {
            log("Unable to start call, failed to interpret URL: \(url)", level: .error)
            return nil
        }
        
        guard let call = linphoneCore.inviteAddress(addr: address) else {
            log("Unable to start call, linphone did not create a call object", level: .error)
            return nil
        }
        
        return VoIPLibCall(linphoneCall: call)
    }
    
    func acceptCall(for call: VoIPLibCall) -> Bool {
        do {
            try call.linphoneCall.accept()
            return true
        } catch {
            return false
        }
    }
    
    func endCall(for call: VoIPLibCall) -> Bool {
        do {
            try call.linphoneCall.terminate()
            return true
        } catch {
            return false
        }
    }
    
    private func configureCodecs(core: Core) {
        let codecs = [Codec.OPUS]
        
        linphoneCore?.videoPayloadTypes.forEach { payload in
            _ = payload.enable(enabled: false)
        }
        
        linphoneCore?.audioPayloadTypes.forEach { payload in
            let enable = !codecs.filter { selectedCodec in
                selectedCodec.rawValue.uppercased() == payload.mimeType.uppercased()
            }.isEmpty
            
            _ = payload.enable(enabled: enable)
        }
        
        guard let enabled = linphoneCore?.audioPayloadTypes.filter({ payload in payload.enabled() }).map({ payload in payload.mimeType }).joined(separator: ", ") else {
            log("Unable to log codecs, no core")
            return
        }
        
        log("Enabled codecs: \(enabled)")
    }

    
    func setMicrophone(muted: Bool) {
        linphoneCore.micEnabled = !muted
    }
    
    func setAudio(enabled:Bool) {
        log("Linphone set audio: \(enabled)")
        linphoneCore.activateAudioSession(activated: enabled)
    }
    
    func setHold(call: VoIPLibCall, onHold hold:Bool) -> Bool {
        do {
            if hold {
                log("Pausing VoIPLibCall.")
                try call.pause()
            } else {
                log("Resuming VoIPLibCall.")
                try call.resume()
            }
            return true
        } catch {
            return false
        }
    }
    
    func transfer(call: VoIPLibCall, to number: String) -> Bool {
        do {
            try call.linphoneCall.transferTo(referTo: linphoneCore.createAddress(address: number))
            log("Transfer was successful")
            return true
        } catch (let error) {
            log("Transfer failed: \(error)")
            return false
        }
    }
    
    func beginAttendedTransfer(call: VoIPLibCall, to number:String) -> AttendedTransferSession? {
        guard let destinationVoIPLibCall = self.call(to: number) else {
            log("Unable to make VoIPLibCall for target VoIPLibCall")
            return nil
        }
        
        return AttendedTransferSession(from: call, to: destinationVoIPLibCall)
    }
    
    func finishAttendedTransfer(attendedTransferSession: AttendedTransferSession) -> Bool {
        do {
            try attendedTransferSession.from.linphoneCall.transferToAnother(dest: attendedTransferSession.to.linphoneCall)
            log("Transfer was successful")
            return true
        } catch (let error) {
            log("Transfer failed: \(error)")
            return false
        }
    }
    
    func sendDtmf(call: VoIPLibCall, dtmf: String) {
        do {
            try call.linphoneCall.sendDtmfs(dtmfs: dtmf)
        } catch (let error) {
            log("Sending dtmf failed: \(error)")
            return
        }
    }
    
    func provideCallInfo(call: VoIPLibCall) -> String {
        return CallInfoProvider(VoIPLibCall: call).provide()
    }
    
    func onLogMessageWritten(logService: LoggingService, domain: String, level: LogLevel, message: String) {
        config?.logListener(message)
    }
    
    internal func refreshRegistration() {
        linphoneCore.refreshRegisters()
    }
    
    private var ringbackPath: String {
        Bundle.main.path(forResource: "ringback", ofType: "wav") ?? ""
    }
}
