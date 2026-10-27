import Foundation

// MARK: - Colleagues

enum ColleagueAvailabilityStatus: String, Codable {
    case available, doNotDisturb, busy, unknown, offline, availableForColleagues

    init(serverValue: String?) {
        switch serverValue {
        case "do_not_disturb": self = .doNotDisturb
        case "offline": self = .offline
        case "available": self = .available
        case "available_for_colleagues": self = .availableForColleagues
        case "busy": self = .busy
        default: self = .unknown
        }
    }
}

enum ColleagueContext: String, Codable {
    case ringing, inCall

    init?(serverValue: String) {
        switch serverValue {
        case "in_call": self = .inCall
        case "ringing": self = .ringing
        default: return nil
        }
    }
}

enum ColleagueDestinationType: String, Codable {
    case app, voipAccount, fixed, none

    init(serverValue: String?) {
        switch serverValue {
        case "app_account": self = .app
        case "voip_account": self = .voipAccount
        case "fixeddestination": self = .fixed
        default: self = .none
        }
    }
}

struct ColleagueDestination: Codable, Equatable {
    var number: String
    var type: ColleagueDestinationType
}

struct Colleague: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var context: [ColleagueContext] = []
    var status: ColleagueAvailabilityStatus?
    var destination: ColleagueDestination?
    /// True for VoIP accounts that aren't linked to a user; they never have presence.
    var isUnconnectedVoipAccount = false
    var unconnectedNumber: String?

    var number: String? { isUnconnectedVoipAccount ? unconnectedNumber : destination?.number }
    var mostRelevantContext: ColleagueContext? { context.first }

    var isAvailableOnMobileAppOrFixedDestination: Bool {
        guard !isUnconnectedVoipAccount, let type = destination?.type else { return false }
        return [.app, .fixed].contains(type) && status == .unknown
    }

    var isOnline: Bool {
        guard !isUnconnectedVoipAccount else { return false }
        if let status, [.available, .availableForColleagues, .doNotDisturb, .busy].contains(status) {
            return true
        }
        return isAvailableOnMobileAppOrFixedDestination
    }
}

// MARK: - Shared contacts

struct SharedContactPhoneNumber: Codable, Equatable, Hashable {
    var phoneNumberFlat: String
    var phoneNumberPretty: String?
    var callingCode: String?

    enum CodingKeys: String, CodingKey {
        case phoneNumberFlat = "phone_number_flat"
        case phoneNumberPretty = "phone_number_pretty"
        case callingCode = "calling_code"
    }
}

struct SharedContact: Codable, Equatable, Identifiable {
    var id: String?
    var givenName: String?
    var familyName: String?
    var companyName: String?
    var phoneNumbers: [SharedContactPhoneNumber] = []

    enum CodingKeys: String, CodingKey {
        case id
        case givenName = "given_name"
        case familyName = "family_name"
        case companyName = "company_name"
        case phoneNumbers = "phone_numbers"
    }

    private var fullName: String {
        [givenName, familyName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    var displayName: String {
        if !fullName.isEmpty {
            if let companyName, !companyName.isEmpty { return "\(fullName) (\(companyName))" }
            return fullName
        }
        return companyName ?? ""
    }

    var simpleDisplayName: String { fullName.isEmpty ? (companyName ?? "") : fullName }

    var requestBody: [String: Any] {
        [
            "given_name": givenName ?? "",
            "family_name": familyName ?? "",
            "company_name": companyName ?? "",
            "phone_numbers": phoneNumbers.map { ["phone_number_flat": $0.phoneNumberFlat] },
        ]
    }
}

// MARK: - Device contacts

struct DeviceContact: Identifiable, Equatable, Hashable {
    struct LabeledValue: Equatable, Hashable {
        var label: String
        var value: String
    }

    var id: String
    var givenName: String
    var familyName: String
    var company: String
    var phoneNumbers: [LabeledValue]
    var emails: [LabeledValue]
    var thumbnail: Data?

    var displayName: String {
        let name = [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? company : name
    }
}

// MARK: - Unified type

enum Colltact: Identifiable, Equatable, Hashable {
    case contact(DeviceContact)
    case shared(SharedContact)
    case colleague(Colleague)

    var id: String {
        switch self {
        case .contact(let c): return "contact-\(c.id)"
        case .shared(let s): return "shared-\(s.id ?? UUID().uuidString)"
        case .colleague(let c): return "colleague-\(c.id)"
        }
    }

    var displayName: String {
        switch self {
        case .contact(let c): return c.displayName
        case .shared(let s): return s.displayName
        case .colleague(let c): return c.name
        }
    }

    var primaryNumber: String? {
        switch self {
        case .contact(let c): return c.phoneNumbers.first?.value
        case .shared(let s): return s.phoneNumbers.first?.phoneNumberFlat
        case .colleague(let c): return c.number
        }
    }

    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }

    static func == (lhs: Colltact, rhs: Colltact) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
