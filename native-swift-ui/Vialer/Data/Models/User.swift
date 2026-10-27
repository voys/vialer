import Foundation

struct User: Codable, Equatable {
    var uuid: String
    var email: String
    var firstName: String
    var preposition: String
    var lastName: String
    var token: String
    var appAccountUrl: String?
    var webphoneAccountId: String?
    var internalNumber: String?
    var client: Client
    var appAccount: AppAccount?
    var permissions: Set<Permission> = []

    var fullName: String {
        [firstName, preposition, lastName]
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: " ")
    }

    var appAccountId: String? {
        guard let appAccountUrl, let url = URL(string: appAccountUrl) else { return nil }
        return url.pathComponents.last(where: { $0 != "/" && !$0.isEmpty })
    }

    var hasAppAccount: Bool { appAccountId != nil }

    var isAllowedVoipCalling: Bool {
        guard let appAccount else { return false }
        return !appAccount.sipUserId.isEmpty
    }

    var credentials: Credentials { Credentials(email: email, token: token) }

    func hasPermission(_ permission: Permission) -> Bool { permissions.contains(permission) }
}

struct Client: Codable, Equatable {
    var id: Int
    var uuid: String
    var name: String
    var url: String
    var voip: ClientVoipConfig
    var outgoingNumbers: [OutgoingNumber] = []
    var enabledModules: [ClientModule] = []
    var voicemailAccounts: [VoicemailAccount] = []
    var currentTemporaryRedirect: TemporaryRedirect?
    var openingHoursModuleId: String?
}

enum ClientModule: String, Codable {
    case callRecording, transcribeCallRecordings, summarizeCallTranscriptions
}

struct ClientVoipConfig: Codable, Equatable {
    var middlewareUrl: String
    var sipUrl: String

    static let fallback = ClientVoipConfig(
        middlewareUrl: Brand.middlewareURL.absoluteString,
        sipUrl: Brand.sipDomain
    )
}

/// SIP credentials for the app account (`GET mobile/profile`).
struct AppAccount: Codable, Equatable {
    var sipUserId: String
    var password: String
    var useEncryption: Bool
    var useOpus: Bool

    init?(json: [String: Any]) {
        guard let password = json["appaccount_password"] as? String else { return nil }
        let id = json["appaccount_account_id"]
        self.sipUserId = (id as? String) ?? (id as? Int).map(String.init) ?? ""
        self.password = password
        self.useEncryption = json["appaccount_use_encryption"] as? Bool ?? false
        self.useOpus = json["appaccount_use_opus"] as? Bool ?? false
    }
}

enum Permission: String, Codable, CaseIterable {
    case canSeeClientCalls
    case canChangeMobileNumberFallback
    case canViewVoicemailAccounts
    case canChangeOutgoingNumber
    case canViewColleagues
    case canViewVoipAccounts
    case canViewDialPlans
    case canViewStats
    case canChangeOpeningHours
    case canChangeAppAccount
    case canChangeTemporaryRedirect

    static func fromPortal(_ portalPermissions: [String]) -> Set<Permission> {
        let mapping: [String: Permission] = [
            "cdr.view_record": .canSeeClientCalls,
            "permission.change_user": .canChangeMobileNumberFallback,
            "voicemail.view_voicemail": .canViewVoicemailAccounts,
            "phoneaccount.change_phoneaccount": .canChangeOutgoingNumber,
            "permission.list_api_user_basic_info": .canViewColleagues,
            "phoneaccount.list_api_voipaccount_basic_info": .canViewVoipAccounts,
            "routing.view_routing": .canViewDialPlans,
            "stats.view_stats": .canViewStats,
            "openinghours.change_openinghoursgroup": .canChangeOpeningHours,
            "appaccount.change_appaccount": .canChangeAppAccount,
        ]
        var result = Set(portalPermissions.compactMap { mapping[$0] })
        if portalPermissions.contains("business_availability.change_temporary_redirect"),
           result.contains(.canViewVoicemailAccounts) {
            result.insert(.canChangeTemporaryRedirect)
        }
        return result
    }
}

enum OutgoingNumber: Codable, Equatable, Hashable {
    case suppressed
    case number(String, description: String?)

    static let suppressedValue = "suppress"

    init(serverValue: String) {
        self = serverValue == "suppressed" || serverValue == OutgoingNumber.suppressedValue
            ? .suppressed
            : .number(serverValue, description: nil)
    }

    var isSuppressed: Bool { if case .suppressed = self { return true } else { return false } }

    var value: String {
        switch self {
        case .suppressed: return ""
        case .number(let n, _): return n
        }
    }

    var description: String? {
        if case .number(_, let d) = self { return d }
        return nil
    }

    var displayLabel: String {
        switch self {
        case .suppressed: return L10n.main.settings.list.accountInfo.businessNumber.suppressed
        case .number(let n, let d):
            if let d, !d.isEmpty { return "\(n) (\(d))" }
            return n
        }
    }

    static func == (lhs: OutgoingNumber, rhs: OutgoingNumber) -> Bool {
        switch (lhs, rhs) {
        case (.suppressed, .suppressed): return true
        case (.number(let a, _), .number(let b, _)): return a == b
        default: return false
        }
    }

    func hash(into hasher: inout Hasher) { hasher.combine(value) }
}

enum UserAvailabilityStatus: String, Codable, CaseIterable {
    case available
    case availableForColleagues = "available_for_colleagues"
    case doNotDisturb = "do_not_disturb"
    case offline

    var title: String {
        switch self {
        case .available: return L10n.main.settings.list.calling.availability.available.title
        case .availableForColleagues: return L10n.main.settings.list.calling.availability.availableInternally.title
        case .doNotDisturb: return L10n.main.settings.list.calling.availability.dnd.title
        case .offline: return L10n.main.settings.list.calling.availability.offline.title
        }
    }

    var systemImage: String {
        switch self {
        case .available: return "checkmark.circle.fill"
        case .availableForColleagues: return "person.2.fill"
        case .doNotDisturb: return "moon.fill"
        case .offline: return "minus.circle.fill"
        }
    }
}
