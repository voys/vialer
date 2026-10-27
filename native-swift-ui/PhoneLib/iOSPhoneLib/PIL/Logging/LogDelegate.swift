import Foundation

public protocol LogDelegate {
    func onLogReceived(message: String, level: LogLevel)
}
