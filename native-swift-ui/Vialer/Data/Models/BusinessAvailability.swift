import Foundation

struct VoicemailAccount: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var name: String
    var description: String?
    var uuid: String = ""

    var displayName: String {
        if let description, !description.trimmingCharacters(in: .whitespaces).isEmpty {
            return "\(name) - \(description)"
        }
        return name
    }

    init?(json: [String: Any]) {
        guard let name = json["name"] as? String else { return nil }
        if let id = json["id"] as? String { self.id = id } else if let id = json["id"] as? Int { self.id = String(id) } else { return nil }
        self.name = name
        self.description = json["description"] as? String
        self.uuid = json["uuid"] as? String ?? ""
    }
}

struct TemporaryRedirect: Codable, Equatable {
    var id: String?
    var endsAt: Date
    /// Nil when the destination isn't one of the client's voicemail accounts.
    var voicemail: VoicemailAccount?

    var destinationName: String { voicemail?.displayName ?? N("temporaryRedirect.destination.unknown") }

    var requestBody: [String: Any] {
        var destination: [String: Any] = ["type": "VOICEMAIL", "id": voicemail?.id ?? ""]
        if let uuid = voicemail?.uuid, !uuid.isEmpty { destination["uuid"] = uuid }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return ["end": formatter.string(from: endsAt), "destination": destination]
    }
}
