import Foundation
import Observation
import UIKit

/// A call the user asked for that is waiting on the outgoing number prompt.
struct PendingCall: Identifiable {
    let id = UUID()
    let destination: String
}

enum CallThroughError: Error {
    case noMobileNumber, invalidDestination, unsupportedRegion, isoCodeNotFound, numberTooLong, failed

    var message: String {
        switch self {
        case .noMobileNumber: return L10n.main.call.error.callThrough.mobile.noMobileNumber
        case .invalidDestination: return L10n.main.call.error.callThrough.invalidDestination
        case .unsupportedRegion: return N("callThrough.error.unsupportedRegion")
        case .isoCodeNotFound: return N("callThrough.error.isoCodeNotFound")
        case .numberTooLong: return L10n.main.call.error.callThrough.numberTooLong.numberTooLong
        case .failed: return N("callThrough.error.failed")
        }
    }
}

/// Routes outgoing calls: shows the outgoing number prompt when needed, then starts the call
/// over VoIP or, when VoIP is unavailable, via call-through on the mobile network.
@MainActor
@Observable
final class OutgoingCallCoordinator {
    var pendingPrompt: PendingCall?

    private let session: SessionManager
    private let calls: CallManager
    private let api = VoipgridAPI()
    private let store = LocalStore.shared

    init(session: SessionManager, calls: CallManager) {
        self.session = session
        self.calls = calls
    }

    func call(_ destination: String) {
        let cleaned = destination.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
        guard !cleaned.isEmpty else { return }
        if shouldPromptForOutgoingNumber(destination: cleaned) {
            pendingPrompt = PendingCall(destination: cleaned)
        } else {
            Task { await start(cleaned) }
        }
    }

    /// Called by the prompt once the outgoing number is settled.
    func promptCompleted(_ pending: PendingCall) {
        pendingPrompt = nil
        Task { await start(pending.destination) }
    }

    func promptCancelled() { pendingPrompt = nil }

    private func shouldPromptForOutgoingNumber(destination: String) -> Bool {
        guard let user = session.user else { return false }
        if destination.isInternalNumber { return false }
        if !user.hasPermission(.canChangeOutgoingNumber) { return false }
        if user.client.outgoingNumbers.count < 2 { return false }
        if store.bool(.doNotShowOutgoingNumberSelector) { return false }
        return true
    }

    private func start(_ destination: String) async {
        if session.canUseVoip {
            await calls.call(destination)
        } else {
            await callThrough(destination)
        }
    }

    // MARK: Call-through

    private func callThrough(_ destination: String) async {
        Metrics.track("call-through-call-started")
        do {
            let regionNumber = try await retrieveRegionNumber(for: destination)
            guard let url = URL(string: "tel:\(regionNumber)") else { throw CallThroughError.failed }
            AppLog.info("Starting call-through call")
            LocalStore.shared.setString(destination, for: .lastDialedNumber)
            await UIApplication.shared.open(url)
        } catch let error as CallThroughError {
            AppLog.warning("Call-through failed: \(error)")
            calls.failure = .message(error.message)
        } catch {
            AppLog.warning("Call-through failed: \(error)")
            calls.failure = .message(CallThroughError.failed.message)
        }
    }

    private func retrieveRegionNumber(for destination: String) async throws -> String {
        guard !session.settings.mobileNumber.isEmpty else { throw CallThroughError.noMobileNumber }
        let normalized = try normalize(destination)
        return try await api.callThroughRegionNumber(destination: normalized)
    }

    /// Approximates the Flutter libphonenumber normalisation: internal numbers pass through,
    /// `00` becomes `+`, and national numbers get the country code of the user's own numbers.
    private func normalize(_ number: String) throws -> String {
        if number.isInternalNumber { return number }
        var number = number
        if number.hasPrefix("00") { number = "+" + number.dropFirst(2) }
        if number.hasPrefix("+") { return number }
        guard number.count <= 15 else { throw CallThroughError.numberTooLong }
        let callingCode = try findCallingCode()
        let national = number.hasPrefix("0") ? String(number.dropFirst()) : number
        return "+\(callingCode)\(national)"
    }

    private func findCallingCode() throws -> String {
        let supported = ["31", "49", "32", "27"]
        for number in [session.settings.outgoingNumber.value, session.settings.mobileNumber] {
            if let code = supported.first(where: { number.hasPrefix("+\($0)") }) { return code }
        }
        AppLog.warning("Unable to find a calling code from the outgoing or mobile number")
        throw CallThroughError.isoCodeNotFound
    }
}

extension String {
    /// Matches the Flutter rule: short numbers not starting with 0 or + are internal extensions.
    var isInternalNumber: Bool { count <= 10 && !hasPrefix("0") && !hasPrefix("+") }
}
