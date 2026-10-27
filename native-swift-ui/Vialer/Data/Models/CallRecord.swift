import Foundation

enum CallRecordDirection: String, Codable { case inbound, outbound }
enum CallRecordType: String, Codable { case colleague, outside }
enum CallerType: String, Codable { case webphone, app, account, other }

struct CallParty: Codable, Equatable {
    var number: String
    var type: CallerType
    var name: String?

    var hasName: Bool { !(name ?? "").isEmpty }
    var label: String { hasName ? name! : number }
}

struct CallRecord: Identifiable, Codable, Equatable {
    var id: String
    var callType: CallRecordType
    var callDirection: CallRecordDirection
    var answered: Bool
    var answeredElsewhere: Bool
    var duration: TimeInterval
    var date: Date
    var caller: CallParty
    var destination: CallParty
    var summary: String?

    // Client-wide call fields (nil for personal calls).
    var didTargetLoggedInUser: Bool?
    var wasInitiatedByLoggedInUser: Bool?
    var didTargetColleague: Bool?
    var wasInitiatedByColleague: Bool?

    var wasMissed: Bool { !answered }

    /// A colleague call to our app account is shown as inbound, matching the Flutter app.
    var direction: CallRecordDirection {
        let isInboundForApp = callDirection == .outbound && callType == .colleague && destination.type == .app
        return isInboundForApp ? .inbound : callDirection
    }

    var isInbound: Bool { direction == .inbound }
    var isOutbound: Bool { direction == .outbound }
    var thirdPartyNumber: String { isInbound ? caller.number : destination.number }
    var thirdPartyName: String? { isInbound ? caller.name : destination.name }
    var isIncomingAndAnsweredElsewhere: Bool { answeredElsewhere && isInbound }
    var isInternal: Bool { callType == .colleague }

    var displayLabel: String {
        if let name = thirdPartyName, !name.isEmpty { return name }
        return thirdPartyNumber
    }
}

/// Raw `v2/call/personalized` and `v2/call/non-personalized` items.
struct VoipgridCallRecord: Decodable {
    struct VoipAccount: Decodable {
        let id: Int
        let internalNumber: String
        let description: String?
        let outgoingName: String?
        let outgoingNumber: String?
    }

    struct FixedDestination: Decodable {
        let id: Int
        let phoneNumber: String
        let description: String?
    }

    struct From: Decodable {
        let type: String
        let phoneNumber: String
        let dialedNumber: String?
        let callerName: String?
        let voipAccount: VoipAccount?
        let userInternalNumber: String?
    }

    struct To: Decodable {
        let type: String
        let phoneNumber: String
        let voipAccount: VoipAccount?
        let fixedDestination: FixedDestination?
    }

    let id: String
    let type: String
    let answered: Bool
    let isAnsweredElsewhere: Bool
    let startTime: String
    let direction: String
    let durationInSeconds: Int
    let from: From
    let to: To
    let summary: String?

    private static let dateFormatters: [DateFormatter] = {
        ["yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss"].map {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = $0
            return f
        }
    }()

    private var parsedDate: Date {
        for f in Self.dateFormatters {
            if let d = f.date(from: startTime) { return d }
        }
        return ISO8601DateFormatter().date(from: startTime) ?? Date()
    }

    func toCallRecord(userPhoneAccountIds: [Int]? = nil) -> CallRecord {
        var record = CallRecord(
            id: id,
            callType: type == "colleague_call" ? .colleague : .outside,
            callDirection: direction == "outgoing" ? .outbound : .inbound,
            answered: answered,
            answeredElsewhere: isAnsweredElsewhere,
            duration: TimeInterval(durationInSeconds),
            date: parsedDate,
            caller: Self.mapCaller(from),
            destination: Self.mapDestination(to),
            summary: summary
        )
        if let ids = userPhoneAccountIds {
            let targetUser = to.voipAccount.map { ids.contains($0.id) } ?? false
            let initiatedByUser = from.voipAccount.map { ids.contains($0.id) } ?? false
            record.didTargetLoggedInUser = targetUser
            record.wasInitiatedByLoggedInUser = initiatedByUser
            record.didTargetColleague = !targetUser && to.voipAccount != nil
            record.wasInitiatedByColleague = !initiatedByUser && from.voipAccount != nil
        }
        return record
    }

    private static func mapCaller(_ from: From) -> CallParty {
        var name: String?
        var number: String
        if let account = from.voipAccount {
            name = account.description
            number = account.internalNumber
        } else if let callerName = from.callerName, !callerName.isEmpty {
            name = callerName
            number = from.phoneNumber
        } else {
            number = from.phoneNumber
        }
        if let internalNumber = from.userInternalNumber, !internalNumber.trimmingCharacters(in: .whitespaces).isEmpty {
            number = internalNumber
        }
        return CallParty(number: number, type: CallerType(rawValue: from.type) ?? .other, name: name)
    }

    private static func mapDestination(_ to: To) -> CallParty {
        var name: String?
        var number: String
        if let account = to.voipAccount {
            name = account.description
            number = account.internalNumber
        } else if let fixed = to.fixedDestination {
            name = fixed.description
            number = fixed.phoneNumber
        } else {
            number = to.phoneNumber
        }
        return CallParty(number: number, type: CallerType(rawValue: to.type) ?? .other, name: name)
    }
}
