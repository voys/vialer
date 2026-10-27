import Foundation

/// Holodeck business-availability service (temporary redirect).
struct BusinessAvailabilityAPI {
    private let client = HTTPClient.shared

    private func url(clientUuid: String, suffix: String = "") -> URL {
        var u = Brand.businessAvailabilityURL.appendingPathComponent("\(clientUuid)/temporary-redirect")
        if !suffix.isEmpty { u = u.appendingPathComponent(suffix) }
        return u
    }

    func currentRedirect(clientUuid: String, voicemails: [VoicemailAccount]) async throws -> TemporaryRedirect? {
        let response = try await client.send(.get, url(clientUuid: clientUuid), auth: .bearer)
        guard response.isSuccessful, let json = response.jsonObject(),
              let id = json["id"].flatMap({ ($0 as? String) ?? ($0 as? Int).map(String.init) }),
              let end = json["end"] as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        guard let endsAt = formatter.date(from: end) ?? plain.date(from: end) else { return nil }
        let destinationId = (json["destination"] as? [String: Any])?["id"]
        let destinationIdString = (destinationId as? String) ?? (destinationId as? Int).map(String.init)
        let voicemail = voicemails.first { $0.id == destinationIdString }
        return TemporaryRedirect(id: id, endsAt: endsAt, voicemail: voicemail)
    }

    func create(clientUuid: String, redirect: TemporaryRedirect) async -> Bool {
        let response = try? await client.send(.post, url(clientUuid: clientUuid), json: redirect.requestBody, auth: .bearer)
        return response?.isSuccessful ?? false
    }

    func update(clientUuid: String, redirect: TemporaryRedirect) async -> Bool {
        guard let id = redirect.id else { return false }
        let response = try? await client.send(.put, url(clientUuid: clientUuid, suffix: id), json: redirect.requestBody, auth: .bearer)
        return response?.isSuccessful ?? false
    }

    func delete(clientUuid: String, id: String) async -> Bool {
        let response = try? await client.send(.delete, url(clientUuid: clientUuid, suffix: id), auth: .bearer)
        return response?.isSuccessful ?? false
    }
}

/// Holodeck number-normalisation service.
struct PhoneNumberAPI {
    struct Validation {
        let isValid: Bool
        let flat: String?
        let pretty: String?
        let type: String?
    }

    private let client = HTTPClient.shared

    func validate(_ number: String, acceptExtension: Bool = false) async -> Validation {
        // The service does not decode %2B, so the leading "+" must be sent raw, as Flutter's
        // `Uri.parse('normalise/$number')` does.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+"))
        let encoded = number.addingPercentEncoding(withAllowedCharacters: allowed) ?? number
        let invalid = Validation(isValid: false, flat: nil, pretty: nil, type: nil)
        guard let url = URL(string: Brand.phoneNumberValidationURL.absoluteString + "normalise/\(encoded)") else { return invalid }
        do {
            let response = try await client.send(.get, url, query: ["accept_extension": acceptExtension ? "true" : "false"], auth: .bearer)
            guard response.isSuccessful, let json = response.jsonObject() else {
                AppLog.warning("Validate phone number failed: \(response.status) \(response.bodyString) url=\(url.absoluteString)")
                return invalid
            }
            let result = Validation(
                isValid: json["is_valid"] as? Bool ?? false,
                flat: json["dial_number"] as? String,
                pretty: json["international_formatted"] as? String,
                type: json["number_type"] as? String
            )
            AppLog.info("Validated phone number: valid=\(result.isValid) type=\(result.type ?? "-") flat=\(result.flat ?? "-") pretty=\(result.pretty ?? "-")")
            return result
        } catch {
            AppLog.warning("Validate phone number failed: \(error)")
            return invalid
        }
    }

    /// The Flutter `StrictlyValidateMobilePhoneNumber`: must be a mobile number typed in its
    /// canonical flat or pretty form.
    func isStrictlyValidMobileNumber(_ number: String) async -> Bool {
        let result = await validate(number, acceptExtension: false)
        guard result.isValid, result.type?.lowercased() == "mobile" else { return false }
        return result.flat == number || result.pretty == number
    }
}

/// Holodeck feature-announcements service.
struct FeatureAnnouncementsAPI {
    private let client = HTTPClient.shared

    func hasUnreadAnnouncements() async -> Bool {
        let url = Brand.featureAnnouncementsURL.appendingPathComponent("feature-announcements")
        guard let response = try? await client.send(.head, url, query: ["interface": "mobile"], auth: .bearer) else { return false }
        let header = (response.headers["x-unread-announcements"] as? String) ?? (response.headers["X-Unread-Announcements"] as? String) ?? "0"
        return (Int(header) ?? 0) > 0
    }
}
