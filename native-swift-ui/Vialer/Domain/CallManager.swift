import Foundation
import LinphoneWrapper
import linphonesw
import Observation
import AVFoundation
import UIKit

/// A value snapshot of the phone lib's session state, safe to render from SwiftUI.
struct CallSnapshot: Equatable {
    struct CallInfo: Equatable {
        var remoteNumber: String
        var displayName: String
        var heading: String
        var subheading: String
        var state: CallState
        var isInbound: Bool
        var duration: Int
        var isOnHold: Bool
        var mos: Float
        var currentMos: Float

        var prettyDuration: String {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = duration < 3600 ? [.minute, .second] : [.hour, .minute, .second]
            formatter.unitsStyle = .positional
            formatter.zeroFormattingBehavior = .pad
            return formatter.string(from: TimeInterval(duration)) ?? ""
        }

        init(_ call: Call) {
            remoteNumber = call.remoteNumber
            displayName = call.displayName
            heading = call.remotePartyHeading
            subheading = call.remotePartySubheading
            state = call.state
            isInbound = call.direction == .inbound
            duration = call.duration
            isOnHold = call.isOnHold
            mos = call.mos
            currentMos = call.currentMos
        }
    }

    var activeCall: CallInfo?
    var inactiveCall: CallInfo?
    var currentRoute: AudioRoute
    var availableRoutes: [AudioRoute]
    var bluetoothDeviceName: String?
    var isMuted: Bool

    init(_ state: CallSessionState) {
        activeCall = state.activeCall.map(CallInfo.init)
        inactiveCall = state.inactiveCall.map(CallInfo.init)
        currentRoute = state.audioState.currentRoute
        availableRoutes = state.audioState.availableRoutes
        bluetoothDeviceName = state.audioState.bluetoothDeviceName
        isMuted = state.audioState.isMicrophoneMuted
    }
}

enum CallFailure: Identifiable {
    case alreadyInCall, rejectedByCallKit, unableToRegister, noMicrophonePermission, voipNotAvailable, unknown
    case message(String)

    var id: String { message }

    var message: String {
        switch self {
        case .message(let text): return text
        case .alreadyInCall: return L10n.main.call.error.voip.inCall
        case .rejectedByCallKit: return N("call.failed.rejectedByCallKit")
        case .unableToRegister: return L10n.main.call.error.voip.unableToRegister
        case .noMicrophonePermission: return L10n.main.call.error.voip.noMicrophonePermission(appName: Brand.appName)
        case .voipNotAvailable: return N("call.failed.voipNotAvailable")
        case .unknown: return N("call.failed.unknown")
        }
    }
}

enum CallPhase: Equatable {
    case idle
    case ringing
    case starting
    case inCall
    case transferring
    case ended
}

/// Wraps the copied iOS phone lib (PIL) behind an observable facade.
@MainActor
@Observable
final class CallManager: NSObject {
    private(set) var snapshot: CallSnapshot?
    private(set) var phase: CallPhase = .idle
    private(set) var hasStarted = false
    var isTransferAborted = false
    var failure: CallFailure?
    /// True while the call screen should be shown.
    var isCallScreenPresented = false
    /// Last call that ended, kept briefly so the call screen can show the final state.
    private(set) var lastEndedCall: CallSnapshot.CallInfo?
    /// Audio routes used during the current call, reported with call ratings.
    private var usedRoutes: Set<AudioRoute> = []
    /// True once the MOS has been below the threshold for the minimum duration.
    private(set) var showPoorConnectionWarning = false
    private var poorQualityTask: Task<Void, Never>?
    private static let badQualityMosThreshold: Float = 2
    private static let badQualityMinDuration: Double = 5
    /// Called when a call ends, after the call screen has been dismissed.
    var onCallEnded: (CallSnapshot.CallInfo, Set<AudioRoute>) -> Void = { _, _ in }

    let middleware = CallwakerMiddleware()
    private var pil: PIL?
    private var listener: EventListener?
    private var dismissTask: Task<Void, Never>?

    var isInCall: Bool { snapshot?.activeCall != nil && phase != .ended }

    /// Prefers the brand's own ringtone, like the Flutter AppDelegate.
    var ringtonePath: String {
        let branded = "ringtone-\(Brand.identifier)"
        if Bundle.main.path(forResource: branded, ofType: "wav") != nil { return "\(branded).wav" }
        return Bundle.main.path(forResource: "ringtone", ofType: "wav") != nil ? "ringtone.wav" : ""
    }

    /// Debug-only: shows the call screen with a fake connected call for simulator previews.
    func installPreviewCall() {
        let call = Call(
            remoteNumber: "+31612345678", displayName: "Alex Bakker", state: .connected, direction: .inbound,
            duration: 125, isOnHold: false, uuid: UUID(), mos: 4.2, currentMos: 4.1, contact: nil, reason: ""
        )
        let audio = AudioState(currentRoute: .phone, availableRoutes: [.phone, .speaker], bluetoothDeviceName: nil, isMicrophoneMuted: false)
        snapshot = CallSnapshot(CallSessionState(activeCall: call, inactiveCall: nil, audioState: audio))
        phase = .inCall
        isCallScreenPresented = true
    }

    // MARK: Lifecycle

    /// Starts (or re-registers) the phone lib for the given user.
    func start(user: User, settings: Settings) {
        guard settings.useVoip, let account = user.appAccount, !account.sipUserId.isEmpty else {
            AppLog.info("VoIP not enabled or no app account, not starting phone lib")
            return
        }
        let auth = Auth(
            username: account.sipUserId,
            password: account.password,
            domain: user.client.voip.sipUrl,
            port: account.useEncryption ? 5061 : 5060,
            secure: account.useEncryption
        )
        let preferences = Preferences(
            useApplicationRingtone: !settings.usePhoneRingtone,
            includesCallsInRecents: settings.showCallsInNativeRecents
        )

        if let pil {
            pil.preferences = preferences
            if pil.auth != auth {
                pil.auth = auth
                pil.start { success in AppLog.info("Phone lib restarted, success=\(success)") }
            }
            return
        }

        let setup = ApplicationSetup(
            middleware: middleware,
            requestCallUi: { [weak self] in
                Task { @MainActor in self?.presentCallScreen() }
            },
            userAgent: BuildInfo.userAgent,
            logDelegate: PhoneLibLogDelegate(),
            notifyOnMissedCall: true,
            ringtonePath: ringtonePath
        )
        do {
            let pil = try startIOSPIL(applicationSetup: setup, auth: auth, preferences: preferences)
            let listener = EventListener { [weak self] event in
                Task { @MainActor in self?.handle(event) }
            }
            pil.events.listen(delegate: listener)
            self.pil = pil
            self.listener = listener
            hasStarted = true
            AppLog.info("Phone lib started")
            // Pick up a call that was answered via CallKit before the UI was ready.
            refreshSnapshot()
            if let active = snapshot?.activeCall, active.state != .ended {
                phase = active.state == .connected ? .inCall : .ringing
                if active.state == .connected { presentCallScreen() }
            }
        } catch {
            ErrorTracking.capture(error, context: "startIOSPIL")
        }
    }

    func updatePreferences(settings: Settings) {
        pil?.preferences = Preferences(
            useApplicationRingtone: !settings.usePhoneRingtone,
            includesCallsInRecents: settings.showCallsInNativeRecents
        )
    }

    private var linphoneLogForwarder: LinphoneLogForwarder?

    var isAdvancedLoggingEnabled: Bool { linphoneLogForwarder != nil }

    func setAdvancedLogging(_ enabled: Bool) {
        guard enabled != isAdvancedLoggingEnabled else { return }
        if enabled {
            let forwarder = LinphoneLogForwarder()
            LoggingService.Instance.addDelegate(delegate: forwarder)
            linphoneLogForwarder = forwarder
            AppLog.info("Advanced VoIP logging enabled")
        } else if let forwarder = linphoneLogForwarder {
            LoggingService.Instance.removeDelegate(delegate: forwarder)
            linphoneLogForwarder = nil
            AppLog.info("Advanced VoIP logging disabled")
        }
    }

    /// Unregisters from SIP and clears credentials; the PIL itself cannot be destroyed.
    func stop() async {
        guard let pil else { return }
        await withCheckedContinuation { continuation in
            pil.unregister { continuation.resume() }
        }
        pil.stop()
        hasStarted = false
        AppLog.info("Phone lib stopped")
    }

    // MARK: Actions

    func call(_ number: String) async {
        guard let pil, hasStarted else {
            failure = .voipNotAvailable
            return
        }
        guard await requestMicrophonePermission() else {
            failure = .noMicrophonePermission
            return
        }
        let normalized = number.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
        AppLog.info("Starting VoIP call")
        phase = .starting
        isTransferAborted = false
        LocalStore.shared.setString(normalized, for: .lastDialedNumber)
        Metrics.track("voip-call-started", ["direction": "outbound"])
        pil.call(number: normalized)
    }

    func answer() async {
        guard await requestMicrophonePermission() else { return }
        pil?.actions.answer()
    }

    func decline() { pil?.actions.decline() }
    func end() { pil?.actions.end() }
    func toggleMute() { pil?.audio.toggleMute(); refreshSnapshot() }
    func toggleHold() { pil?.actions.toggleHold() }
    func hold() { pil?.actions.hold() }
    func sendDtmf(_ digits: String) { pil?.actions.sendDtmf(digits, playToneLocally: true) }
    func routeAudio(_ route: AudioRoute) { pil?.audio.routeAudio(route) }
    func launchAudioRoutePicker() { pil?.audio.launchAudioRoutePicker() }

    func beginTransfer(to number: String) {
        let normalized = number.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
        pil?.actions.beginAttendedTransfer(number: normalized)
    }

    func mergeTransfer() { pil?.actions.completeAttendedTransfer() }
    func performEchoCancellationCalibration() { pil?.performEchoCancellationCalibration() }
    var linphoneVersion: String? { pil?.linphoneVersion }

    func playTone(_ digit: Character) {
        if let pil { pil.playToneLocally(digit: digit) } else { SystemTones().playForDigit(digit: digit) }
    }

    func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    // MARK: Events

    private func handle(_ event: Event) {
        switch event {
        case .outgoingCallStarted(let state):
            apply(state)
            phase = .starting
            presentCallScreen()
        case .incomingCallReceived(let state):
            apply(state)
            phase = .ringing
            Metrics.track("voip-call-started", ["direction": "inbound"])
        case .callConnected(let state):
            apply(state)
            phase = snapshot?.inactiveCall != nil ? .transferring : .inCall
            presentCallScreen()
        case .callEnded(let state):
            lastEndedCall = state.activeCall.map(CallSnapshot.CallInfo.init)
            apply(state)
            phase = .ended
            announce(L10n.main.call.ended.message)
            Metrics.track("voip-call-ended", ["reason": state.activeCall?.reason ?? ""])
            middleware.currentCallInfo = nil
            scheduleDismiss(after: 2)
        case .callDurationUpdated(let state), .audioStateUpdated(let state), .callStateUpdated(let state):
            apply(state)
        case .attendedTransferStarted(let state):
            apply(state)
            phase = .transferring
        case .attendedTransferAborted(let state):
            apply(state)
            isTransferAborted = true
            phase = .inCall
            announce(L10n.main.call.transfer.abort.message)
        case .attendedTransferConnected(let state):
            apply(state)
        case .attendedTransferEnded(let state):
            apply(state)
            phase = .ended
            announce(L10n.main.call.transfer.complete.message)
            scheduleDismiss(after: 2)
        case .outgoingCallSetupFailed(let reason):
            phase = .idle
            failure = CallFailure(reason)
            Metrics.track("call-outbound-failed", ["reason": "\(reason)"])
        case .incomingCallSetupFailed(let reason):
            AppLog.warning("Incoming call setup failed: \(reason)")
        }
    }

    private func apply(_ state: CallSessionState) {
        snapshot = CallSnapshot(state)
        usedRoutes.insert(state.audioState.currentRoute)
        updatePoorConnectionWarning(state.activeCall)
        if phase == .ended, state.activeCall != nil, state.activeCall?.state != .ended {
            // A new call started before the previous screen dismissed.
            phase = state.activeCall?.state == .connected ? .inCall : .starting
        }
    }

    /// Mirrors the Flutter rule: a valid MOS (call older than 2 s) under 2 for at least 5 s.
    private func updatePoorConnectionWarning(_ call: Call?) {
        let isBad = call.map { $0.currentMos > 0 && $0.duration >= 2 && $0.currentMos < Self.badQualityMosThreshold } ?? false
        if !isBad || phase == .ended {
            poorQualityTask?.cancel()
            poorQualityTask = nil
            showPoorConnectionWarning = false
            return
        }
        guard poorQualityTask == nil, !showPoorConnectionWarning else { return }
        poorQualityTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.badQualityMinDuration))
            guard let self, !Task.isCancelled else { return }
            showPoorConnectionWarning = true
            Metrics.track("ongoing-call-connectivity-warning-shown", ["mos": call?.mos ?? 0, "currentMos": call?.currentMos ?? 0])
        }
    }

    private func announce(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private func refreshSnapshot() {
        if let pil { snapshot = CallSnapshot(pil.sessionState) }
    }

    private func presentCallScreen() {
        dismissTask?.cancel()
        isCallScreenPresented = true
    }

    private func scheduleDismiss(after seconds: Double) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            if self.phase == .ended {
                self.isCallScreenPresented = false
                self.phase = .idle
                self.snapshot = nil
                let routes = self.usedRoutes
                self.usedRoutes = []
                if let ended = self.lastEndedCall {
                    // Give the full-screen cover time to dismiss before presenting anything else.
                    try? await Task.sleep(for: .seconds(0.6))
                    self.onCallEnded(ended, routes)
                }
            }
        }
    }

    /// Called when the app returns to the foreground, to drop a stale screen.
    func reconcileOnForeground() {
        refreshSnapshot()
        if isCallScreenPresented, snapshot?.activeCall == nil {
            isCallScreenPresented = false
            phase = .idle
        }
    }
}

private extension CallFailure {
    init(_ reason: CallSetupFailedReason) {
        switch reason {
        case .inCall: self = .alreadyInCall
        case .rejectedByCallKit: self = .rejectedByCallKit
        case .unableToRegister: self = .unableToRegister
        case .unknown: self = .unknown
        }
    }
}

private final class EventListener: PILEventDelegate {
    private let handler: (Event) -> Void
    init(_ handler: @escaping (Event) -> Void) { self.handler = handler }
    func onEvent(event: Event) { handler(event) }
}

/// Forwards raw Linphone log lines into the app log while "advanced VoIP logging" is on. Like the
/// Flutter app, the toggle is not persisted and is off again after a restart.
private final class LinphoneLogForwarder: LinphoneLoggingServiceDelegate {
    func onLogMessageWritten(logService: LoggingService, domain: String, level: LinphoneLogLevel, message: String) {
        AppLog.info("Linphone[\(domain)]: \(message)")
    }
}

private struct PhoneLibLogDelegate: LogDelegate {
    func onLogReceived(message: String, level: Vialer.LogLevel) {
        switch level {
        case .error: AppLog.error("PIL: \(message)")
        case .warning: AppLog.warning("PIL: \(message)")
        default: AppLog.info("PIL: \(message)")
        }
    }
}
