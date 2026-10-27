import Foundation
import linphonesw

internal class LinphoneAudio {
    private let manager: LinphoneManager
    
    private lazy var core: Core = {
        manager.linphoneCore!
    }()
    
    init(manager: LinphoneManager) {
        self.manager = manager
    }
    
    func routeAudio(to route: AudioRoute, onlySetDefaults: Bool = false) {
        let outputRoute = route
        
        // We don't want to set the input route to speaker, ever. So if the output route is to speaker,
        // we will assume they want the input to be [.bluetooth] if there is one available, otherwise
        // just [.phone].
        let fallbackInputRoute = hasAudioRouteAvailable(.bluetooth) ? .bluetooth : AudioRoute.phone
        let inputRoute = route == .speaker ? fallbackInputRoute : route
        
        core.audioDevices.forEach { device in
            if outputRoute.matchesLinphoneDevice(device) {
                if onlySetDefaults {
                    core.defaultOutputAudioDevice = device
                } else {
                    core.outputAudioDevice = device
                }
            }
            
            if inputRoute.matchesLinphoneDevice(device) {
                if onlySetDefaults {
                    core.defaultInputAudioDevice = device
                } else {
                    core.inputAudioDevice = device
                }
            }
        }
    }
    
    func hasAudioRouteAvailable(_ route: AudioRoute) -> Bool {
        return findDevice(route) != nil
    }
    
    func findDevice(_ route: AudioRoute) -> AudioDevice? {
        return core.audioDevices.filter { device in
            route.matchesLinphoneDevice(device)
        }.first
    }
    
    var availableRoutes: [AudioRoute] {
        var routes: [AudioRoute] = [.speaker]
        
        if hasAudioRouteAvailable(.bluetooth) {
            routes.append(.bluetooth)
        }
        
        if hasAudioRouteAvailable(.phone) {
            routes.append(.phone)
        }
        
        return routes
    }
    
    var currentAudioDevice: AudioDevice? {
        return core.outputAudioDevice
    }
    
    /// Linphone reports no output device while a call's audio stream is stopped (e.g. on hold),
    /// so we keep the last real route rather than falsely reporting the earpiece.
    private var lastKnownRoute: AudioRoute = .phone

    var currentRoute: AudioRoute {
        if let route = core.outputAudioDevice?.asRoute {
            lastKnownRoute = route
        } else if core.callsNb == 0 {
            lastKnownRoute = .phone
        }

        return lastKnownRoute
    }
    
    var audioDevicesAsString: String {
        core.audioDevicesAsString
    }
}

internal extension AudioDevice {
    var asRoute: AudioRoute {
        switch type {
            case .AuxLine, .Microphone, .Earpiece, .GenericUsb, .Telephony, .Unknown: return .phone
            case .Speaker: return .speaker
            case .Bluetooth, .BluetoothA2DP, .Headset, .Headphones, .HearingAid: return .bluetooth
        }
    }
}

internal extension AudioRoute {
    /// A single audio route for us will map to many different types of native routes.
    var asLinphoneRoutes: Set<AudioDevice.Kind> {
        switch self {
            case .speaker: return [.Speaker]
            case .phone: return [.Microphone]
            case .bluetooth: return [.Bluetooth, .BluetoothA2DP]
        }
    }
    
    func matchesLinphoneDevice(_ device: AudioDevice) -> Bool {
        return asLinphoneRoutes.contains(device.type)
    }
}

internal extension Core {
    var audioDevicesAsString: String {
        audioDevices.map { device in
            "Name: [\(device.deviceName)], Type: [\(device.type)], ID: [\(device.id)], Capabilities: [\(device.capabilities)]"
        }.joined(separator: "\n")
    }
}
