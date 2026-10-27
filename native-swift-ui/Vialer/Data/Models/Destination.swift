import Foundation

/// The user's ringing device as configured in the portal.
enum Destination: Codable, Equatable, Hashable {
    case unknown
    case notAvailable
    case phoneNumber(id: Int, description: String?, number: String?)
    case phoneAccount(id: Int, description: String, accountId: Int, internalNumber: Int, isOnline: Bool)

    var identifier: Int {
        switch self {
        case .unknown: return 0
        case .notAvailable: return -1
        case .phoneNumber(let id, _, _): return id
        case .phoneAccount(let id, _, _, _, _): return id
        }
    }

    var isOnline: Bool {
        if case .phoneAccount(_, _, _, _, let isOnline) = self { return isOnline }
        return true
    }

    var accountId: Int? {
        if case .phoneAccount(_, _, let accountId, _, _) = self { return accountId }
        return nil
    }

    var description: String {
        switch self {
        case .unknown: return L10n.main.settings.list.calling.unknown
        case .notAvailable: return L10n.main.settings.list.calling.notAvailable
        case .phoneNumber(_, let d, let n): return d?.isEmpty == false ? d! : (n ?? "")
        case .phoneAccount(_, let d, _, let internalNumber, _):
            return d.isEmpty ? String(internalNumber) : d
        }
    }

    var subtitle: String? {
        switch self {
        case .phoneNumber(_, _, let n): return n
        case .phoneAccount(_, _, _, let internalNumber, _): return String(internalNumber)
        default: return nil
        }
    }

    func settingOnline(_ online: Bool) -> Destination {
        if case .phoneAccount(let id, let d, let accountId, let internalNumber, _) = self {
            return .phoneAccount(id: id, description: d, accountId: accountId, internalNumber: internalNumber, isOnline: online)
        }
        return self
    }

    /// Request body for `PUT selecteduserdestination/{id}/`.
    var postParameters: [String: Any] {
        switch self {
        case .phoneAccount: return ["phoneaccount": String(identifier)]
        case .phoneNumber: return ["fixeddestination": String(identifier)]
        default: return ["phoneaccount": NSNull(), "fixeddestination": NSNull()]
        }
    }
}

extension Array where Element == Destination {
    var phoneAccounts: [Destination] { filter { if case .phoneAccount = $0 { return true } else { return false } } }

    func findPhoneAccount(id: String?) -> Destination? {
        guard let id else { return nil }
        return phoneAccounts.first { String($0.identifier) == id }
    }

    func appAccount(for user: User) -> Destination? { findPhoneAccount(id: user.appAccountId) }
    func webphoneAccount(for user: User) -> Destination? { findPhoneAccount(id: user.webphoneAccountId) }

    func deskPhones(for user: User) -> [Destination] {
        let excluded = [appAccount(for: user), webphoneAccount(for: user)].compactMap { $0 }
        return phoneAccounts.filter { !excluded.contains($0) }
    }

    var fixedDestinations: [Destination] {
        filter { if case .phoneNumber = $0 { return true } else { return false } }
    }

    func find(id: Int) -> Destination? { first { $0.identifier == id } }
}
