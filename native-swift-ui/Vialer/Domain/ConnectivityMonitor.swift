import Foundation
import Network
import Observation

/// Tracks whether the device has a usable network path.
@MainActor
@Observable
final class ConnectivityMonitor {
    private(set) var isConnected = true
    private let monitor = NWPathMonitor()
    /// Called when connectivity returns after being lost.
    var onReconnected: () -> Void = {}

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in self?.update(connected) }
        }
        monitor.start(queue: DispatchQueue(label: "connectivity"))
    }

    private func update(_ connected: Bool) {
        let wasConnected = isConnected
        isConnected = connected
        if connected {
            if !wasConnected {
                AppLog.info("Connectivity restored")
                onReconnected()
            }
        } else {
            AppLog.warning("Connectivity lost")
        }
    }
}
