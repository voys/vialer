import Foundation
import linphonesw

#if IOSPHONELIB_PRIVATE
import iOSPhoneLib_Private
#else
import LinphoneWrapper
#endif

internal class LinphoneListener: CoreDelegate {
    
    private let headersToPreserve = ["Remote-Party-ID", "P-Asserted-Identity"]
    
    let linphoneManager:LinphoneManager
    
    init(manager:LinphoneManager) {
        linphoneManager = manager
    }
    
    func onCallStateChanged(core: Core, call: LinphoneCall, state: LinphoneCall.State, message: String) {
        log("OnVoIPLibCallStateChanged, state:\(state) with message:\(message).")

        guard let voipLibCall = VoIPLibCall(linphoneCall: call) else {
            log("Unable to create VoIPLibCall, no remote address")
            return
        }

        guard let delegate = self.linphoneManager.config?.callDelegate else {
            log("Unable to send events as no VoIPLibCall delegate")
            return
        }

        DispatchQueue.main.async {
            switch state {
                case .OutgoingInit:
                    delegate.outgoingCallCreated(voipLibCall)
                case .IncomingReceived:
                    self.preserveHeaders(linphoneCall: call)
                    delegate.incomingCallReceived(voipLibCall)
                case .Connected:
                    delegate.callConnected(voipLibCall)
                case .End, .Error:
                    delegate.callEnded(voipLibCall)
                case .Released:
                    delegate.callReleased(voipLibCall)
                default:
                    delegate.callUpdated(voipLibCall, message: message)
            }
        }
    }
    
    func onTransferStateChanged(core: Core, transferred: LinphoneCall, callState: LinphoneCall.State) {
        guard let delegate = self.linphoneManager.config?.callDelegate else {
            log("Unable to send VoIPLibCall transfer event as no VoIPLibCall delegate")
            return
        }
        
        guard let voipLibVoIPLibCall = VoIPLibCall(linphoneCall: transferred) else {
            log("Unable to create VoIPLibCall, no remote address")
            return
        }
        
        delegate.attendedTransferMerged(voipLibVoIPLibCall)
    }
    
    /**
            Some headers only appear in the initial invite, this will check for any headers we have flagged to be preserved
     and retain them across all iterations of the LinphoneVoIPLibCall.
     */
    private func preserveHeaders(linphoneCall: LinphoneCall) {
        headersToPreserve.forEach { key in
            let value = linphoneCall.getToHeader(headerName: key)
            linphoneCall.params?.addCustomHeader(headerName: key, headerValue: value)
        }
    }
    
    func onAudioDevicesListUpdated(core: Core) {
        log("onAudioDevicesListUpdated: \(core.audioDevicesAsString)")
    }
}
