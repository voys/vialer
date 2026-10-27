import Foundation
import AVFoundation
import AVKit

public class AudioManager {
    
    private let voipLib: VoIPLib
    private let audioSession: AVAudioSession
    private let pil: PIL
    private let callActions: CallActions
    
    private var linphoneAudio: LinphoneAudio {
        voipLib.linphone.linphoneAudio
    }
    
    public var state: AudioState {
        AudioState(
            currentRoute: linphoneAudio.currentRoute,
            availableRoutes: linphoneAudio.availableRoutes,
            bluetoothDeviceName: findBluetoothName(),
            isMicrophoneMuted: isMicrophoneMuted
        )
    }
    
    private lazy var routePickerView: AVRoutePickerView = {
        let routePickerView = AVRoutePickerView()
        routePickerView.isHidden = true
        return routePickerView
    }()
    
    init(pil: PIL, voipLib: VoIPLib, audioSession: AVAudioSession, callActions: CallActions) {
        self.pil = pil
        self.voipLib = voipLib
        self.audioSession = audioSession
        self.callActions = callActions
        
        listenForAudioRouteChangesFromOS()
        setAppropriateDefaults()
    }
    
    public var isMicrophoneMuted: Bool {
        voipLib.isMicrophoneMuted
    }
    
    public func routeAudio(_ route: AudioRoute) {
        // The echo limiter is a brute-force method to prevent echo, it should only be used
        // when it is really necessary, such as when the user is using the phone's speaker.
        if (route == AudioRoute.speaker) {
            pil.calls.list.callArray.forEach { call in
                call.linphoneCall.echoLimiterEnabled = true
                call.linphoneCall.echoCancellationEnabled = false
            }
        } else {
            pil.calls.list.callArray.forEach { call in
                call.linphoneCall.echoLimiterEnabled = false
                call.linphoneCall.echoCancellationEnabled = true
            }
        }
        
        linphoneAudio.routeAudio(to: route)
        
        log("Routed audio to \(route)")
        
        pil.events.broadcast(event: .audioStateUpdated(state: pil.sessionState))
    }
    
    /// Launch a native UI dialog box that allows the user to choose from a list of inputs.
    public func launchAudioRoutePicker() {
        log("Launching native Audio Route Picker")
        
        if let routePickerButton = routePickerView.subviews.first(where: { $0 is UIButton }) as? UIButton {
            routePickerButton.sendActions(for: .touchUpInside)
        }
    }
    
    private func isRouteAvailable(_ route: AudioRoute) -> Bool {
        return linphoneAudio.hasAudioRouteAvailable(.phone)
    }
    
    private func findBluetoothName() -> String? {
        if linphoneAudio.currentRoute == .bluetooth {
            if let currentDevice = linphoneAudio.currentAudioDevice {
                return currentDevice.deviceName
            }
        }
        
        return linphoneAudio.findDevice(.bluetooth)?.deviceName
    }
    
    public func mute() { callActions.mute() }
    
    public func unmute() { callActions.unmute() }
    
    public func toggleMute() { callActions.toggleMute() }
    
    private func setAppropriateDefaults() {
        let route = isRouteAvailable(.bluetooth) ? AudioRoute.bluetooth : .phone
        
        linphoneAudio.routeAudio(
            to: route,
            onlySetDefaults: true
        )
        
        log("Set default audio route to \(route)")
    }
    
    private func listenForAudioRouteChangesFromOS() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }
    
    @objc func handleRouteChange(notification: Notification) {
        setAppropriateDefaults()
        log("Detected audio route change from the OS: \(linphoneAudio.audioDevicesAsString)")
        pil.events.broadcast(event: .audioStateUpdated(state: pil.sessionState))
    }
}
