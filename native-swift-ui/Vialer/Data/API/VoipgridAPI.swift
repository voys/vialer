import Foundation

enum LoginError: Error {
    case twoFactorRequired
    case invalidCredentials
    case needToChangePassword
    case noConnection
    case failed(String)
}

struct SystemUserResponse {
    let uuid: String
    let email: String
    let mobileNumber: String?
    let firstName: String
    let preposition: String
    let lastName: String
    let appAccountUrl: String?
    let outgoingCli: String?
    let clientId: Int
    let clientUuid: String
    let clientName: String
    let clientUrl: String

    init?(json: [String: Any]) {
        guard let uuid = json["uuid"] as? String,
              let email = json["email"] as? String,
              let clientId = json["client_id"] as? Int,
              let clientUuid = json["client_uuid"] as? String else { return nil }
        self.uuid = uuid
        self.email = email
        self.mobileNumber = json["mobile_nr"] as? String
        self.firstName = json["first_name"] as? String ?? ""
        self.preposition = json["preposition"] as? String ?? ""
        self.lastName = json["last_name"] as? String ?? ""
        self.appAccountUrl = json["app_account"] as? String
        self.outgoingCli = json["outgoing_cli"] as? String
        self.clientId = clientId
        self.clientUuid = clientUuid
        self.clientName = json["client_name"] as? String ?? ""
        self.clientUrl = json["client"] as? String ?? ""
    }
}

struct UserDetailsResponse {
    let firstName: String
    let lastName: String
    let preposition: String?
    let internalNumber: String
    let selectedDestinationId: Int?
    let selectedDestination: Destination?
    let availableDestinations: [Destination]
    let useMobileNumberAsFallback: Bool
    let webphoneAccountId: String?
    let enabledModules: [ClientModule]

    init(json: [String: Any]) {
        firstName = json["first_name"] as? String ?? ""
        lastName = json["last_name"] as? String ?? ""
        preposition = json["preposition"] as? String
        internalNumber = Self.string(json["internal_number"])

        let destinations = json["destinations"] as? [String: Any] ?? [:]
        let voipAccounts = (destinations["voip_accounts"] as? [[String: Any]] ?? []).compactMap(Self.voipAccountDestination)
        let fixed = (destinations["fixed_destinations"] as? [[String: Any]] ?? []).compactMap(Self.fixedDestination)
        availableDestinations = fixed + voipAccounts

        if let selected = json["selected_destination"] as? [String: Any] {
            selectedDestinationId = Int(Self.string(selected["id"]))
            if let account = selected["voip_account"] as? [String: Any] {
                selectedDestination = Self.voipAccountDestination(account)
            } else if let fixedDest = selected["fixed_destination"] as? [String: Any] {
                selectedDestination = Self.fixedDestination(fixedDest)
            } else {
                selectedDestination = nil
            }
        } else {
            selectedDestinationId = nil
            selectedDestination = nil
        }

        let app = json["app"] as? [String: Any]
        useMobileNumberAsFallback = app?["use_mobile_number_as_fallback"] as? Bool ?? false
        let webphone = json["webphone"] as? [String: Any]
        webphoneAccountId = (webphone?["voip_account"] as? [String: Any]).map { Self.string($0["id"]) }

        let modules = (json["client"] as? [String: Any])?["modules"] as? [String: Any] ?? [:]
        var enabled: [ClientModule] = []
        if modules["callrecording"] as? Bool == true { enabled.append(.callRecording) }
        let intelligence = modules["intelligence"] as? [String: Any] ?? [:]
        if intelligence["transcribe_callrecordings"] as? Bool == true { enabled.append(.transcribeCallRecordings) }
        if intelligence["summarize_call_transcriptions"] as? Bool == true { enabled.append(.summarizeCallTranscriptions) }
        enabledModules = enabled
    }

    private static func string(_ value: Any?) -> String {
        if let s = value as? String { return s }
        if let i = value as? Int { return String(i) }
        return ""
    }

    private static func voipAccountDestination(_ json: [String: Any]) -> Destination? {
        guard let id = Int(string(json["id"])), let accountId = Int(string(json["account_id"])) else { return nil }
        return .phoneAccount(
            id: id,
            description: json["description"] as? String ?? "",
            accountId: accountId,
            internalNumber: Int(string(json["internal_number"])) ?? 0,
            isOnline: true
        )
    }

    private static func fixedDestination(_ json: [String: Any]) -> Destination? {
        guard let id = Int(string(json["id"])) else { return nil }
        return .phoneNumber(id: id, description: json["description"] as? String, number: json["phone_number"] as? String)
    }
}

/// VoIPGRID API (`https://partner.voys.co/api/`).
struct VoipgridAPI {
    private let client = HTTPClient.shared
    private let base = Brand.voipgridAPIBaseURL

    private func url(_ path: String) -> URL { base.appendingPathComponent(path) }

    // MARK: Authentication

    func requestToken(email: String, password: String, twoFactorCode: String?) async throws -> String {
        var body: [String: Any] = ["email": email, "password": password]
        if let twoFactorCode { body["two_factor_token"] = twoFactorCode }
        let response: HTTPResponse
        do {
            response = try await client.send(.post, url("permission/apitoken/"), json: body, auth: .none)
        } catch HTTPError.noConnection {
            throw LoginError.noConnection
        }
        if twoFactorCode == nil, response.bodyString.contains("two_factor_token") {
            throw LoginError.twoFactorRequired
        }
        guard response.isSuccessful, let token = response.jsonObject()?["api_token"] as? String else {
            AppLog.warning("Authentication failed: \(response.status) \(response.bodyString)")
            throw LoginError.invalidCredentials
        }
        return token
    }

    func getSystemUser(email: String? = nil, token: String? = nil) async throws -> SystemUserResponse {
        let auth: AuthStyle = (email != nil && token != nil) ? .explicit("Token \(email!):\(token!)") : .voipgridAuto
        let response = try await client.send(.get, url("permission/systemuser/profile"), auth: auth)
        if response.bodyString.contains("You need to change your password in the portal") {
            throw LoginError.needToChangePassword
        }
        guard response.isSuccessful, let json = response.jsonObject(), let user = SystemUserResponse(json: json) else {
            throw LoginError.failed("Fetch user failed: \(response.status) \(response.bodyString)")
        }
        return user
    }

    func requestPasswordReset(email: String) async -> Bool {
        let response = try? await client.send(.post, url("permission/password_reset/"), json: ["email": email], auth: .none)
        return response?.isSuccessful ?? false
    }

    func changePassword(email: String, currentPassword: String, newPassword: String) async -> Bool {
        let body = ["email_address": email, "current_password": currentPassword, "new_password": newPassword]
        let response = try? await client.send(.put, url("v2/password"), json: body, auth: .legacyToken)
        return response?.isSuccessful ?? false
    }

    func getAutoLoginToken() async throws -> String {
        let response = try await client.send(.get, url("autologin/token"))
        guard let token = response.jsonObject()?["token"] as? String else {
            throw HTTPError.status(response.status, response.bodyString)
        }
        return token
    }

    // MARK: User data

    func getPermissions() async throws -> Set<Permission> {
        let response = try await client.send(.get, url("v2/users/auth-context"))
        guard response.isSuccessful else { throw HTTPError.status(response.status, response.bodyString) }
        let raw = response.jsonObject()?["permissions"] as? [String] ?? []
        return Permission.fromPortal(raw)
    }

    func getAppAccount() async throws -> AppAccount? {
        let response = try await client.send(.get, url("mobile/profile/"))
        guard response.isSuccessful else { throw HTTPError.status(response.status, response.bodyString) }
        return response.jsonObject().flatMap(AppAccount.init(json:))
    }

    func forceOpusAndEncryption() async {
        _ = try? await client.send(.put, url("mobile/profile/"), json: ["appaccount_use_opus": true, "appaccount_use_encryption": true])
    }

    func getClientVoipConfig() async throws -> ClientVoipConfig {
        let response = try await client.send(.get, url("v2/vialer/middlewares"))
        guard response.isSuccessful, let json = response.jsonObject(),
              let middleware = json["MIDDLEWARE"] as? String, let sip = json["SIP_TLS"] as? String else {
            throw HTTPError.status(response.status, response.bodyString)
        }
        let middlewareUrl = middleware.hasPrefix("https://") ? middleware : "https://\(middleware)"
        return ClientVoipConfig(middlewareUrl: middlewareUrl, sipUrl: sip)
    }

    func getUserDetails() async throws -> UserDetailsResponse {
        let response = try await client.send(.get, url("v2/user/details"))
        guard response.isSuccessful, let json = response.jsonObject() else {
            throw HTTPError.status(response.status, response.bodyString)
        }
        return UserDetailsResponse(json: json)
    }

    func getOutgoingNumbers(clientUuid: String) async throws -> [OutgoingNumber] {
        var numbers: [OutgoingNumber] = []
        var page = 1
        while page <= 20 {
            let response = try await client.send(
                .get, url("v2/clients/\(clientUuid)/callerid_numbers"),
                query: ["page": String(page), "per_page": "500"],
                headers: ["Accept": "application/json;version=2"]
            )
            guard response.isSuccessful, let json = response.jsonObject() else { break }
            for item in json["items"] as? [[String: Any]] ?? [] {
                if let number = item["number"] as? String {
                    numbers.append(.number(number, description: item["description"] as? String))
                }
            }
            guard let next = json["next"] as? String, !next.isEmpty else { break }
            page += 1
        }
        var seen = Set<String>()
        return numbers.filter { seen.insert($0.value).inserted }
    }

    func changeOutgoingNumber(user: User, number: String) async -> Bool {
        guard let appAccountId = user.appAccountId else { return false }
        let body = ["outgoing_caller_identification": ["phone_number": number]]
        let response = try? await client.send(.patch, url("v2/clients/\(user.client.id)/voip_accounts/\(appAccountId)"), json: body)
        return response?.isSuccessful ?? false
    }

    func setDestination(selectedUserDestinationId: Int, destination: Destination) async -> Bool {
        do {
            let response = try await client.send(.put, url("selecteduserdestination/\(selectedUserDestinationId)/"), json: destination.postParameters)
            if !response.isSuccessful {
                AppLog.warning("Set destination failed: \(response.status) \(response.bodyString)")
            }
            return response.isSuccessful
        } catch {
            AppLog.warning("Set destination failed: \(error)")
            return false
        }
    }

    func changeMobileNumber(_ number: String) async -> Bool {
        let response = try? await client.send(.put, url("permission/mobile_number/"), json: ["mobile_nr": number])
        return response?.isSuccessful ?? false
    }

    func setUseMobileNumberAsFallback(user: User, enabled: Bool) async -> Bool {
        let settingsURL = url("v2/clients/\(user.client.id)/users/\(user.uuid)")
        guard let current = try? await client.send(.get, settingsURL), current.isSuccessful,
              let app = current.jsonObject()?["app"] as? [String: Any] else { return false }
        let body: [String: Any] = [
            "app": [
                "mobile_number": app["mobile_number"] ?? NSNull(),
                "use_mobile_number_as_fallback": enabled,
                "voip_account": ["id": (app["voip_account"] as? [String: Any])?["id"] ?? NSNull()],
            ],
        ]
        let response = try? await client.send(.patch, settingsURL, json: body)
        return response?.isSuccessful ?? false
    }

    // MARK: Calls

    /// Returns the regional number to dial so the platform can connect the call via the mobile network.
    func callThroughRegionNumber(destination: String) async throws -> String {
        let response = try await client.send(.get, url("v2/callthrough"), query: ["destination": destination])
        if response.isSuccessful, let number = response.jsonObject()?["phonenumber"] as? String {
            return number
        }
        let body = response.bodyString
        if body.contains("invalid_destination") { throw CallThroughError.invalidDestination }
        if body.contains("no_mobile_number") { throw CallThroughError.noMobileNumber }
        if body.contains("unsupported_region") { throw CallThroughError.unsupportedRegion }
        AppLog.warning("Retrieve region number failed: \(response.status) \(body)")
        throw CallThroughError.failed
    }

    func getPersonalCalls(page: Int, onlyMissed: Bool) async throws -> [CallRecord] {
        let response = try await client.send(
            .get, url("v2/call/personalized"),
            query: ["page": String(page), "per_page": "20", "answered": onlyMissed ? "false" : nil, "timezone": TimeZone.current.identifier]
        )
        guard response.isSuccessful else { throw HTTPError.status(response.status, response.bodyString) }
        return try decodeCallRecords(response).map { $0.toCallRecord() }
    }

    func getClientCalls(page: Int, onlyMissed: Bool, userPhoneAccountIds: [Int]) async throws -> [CallRecord] {
        let response = try await client.send(
            .get, url("v2/call/non-personalized"),
            query: ["page": String(page), "per_page": "20", "answered": onlyMissed ? "false" : nil, "timezone": TimeZone.current.identifier]
        )
        guard response.isSuccessful else { throw HTTPError.status(response.status, response.bodyString) }
        return try decodeCallRecords(response).map { $0.toCallRecord(userPhoneAccountIds: userPhoneAccountIds) }
    }

    private func decodeCallRecords(_ response: HTTPResponse) throws -> [VoipgridCallRecord] {
        if response.data.isEmpty { return [] }
        do {
            return try response.decode([VoipgridCallRecord].self)
        } catch {
            throw HTTPError.decoding(error)
        }
    }

    func getVoicemailAccounts(clientId: Int) async throws -> [VoicemailAccount] {
        try await collect(path: "v2/clients/\(clientId)/voicemails").compactMap(VoicemailAccount.init(json:))
    }

    /// Opening hours modules; only the first module's id is used, for the portal edit page.
    func getOpeningHoursModuleId(clientUuid: String) async -> String? {
        let url = Brand.openingHoursBasicURL.appendingPathComponent("\(clientUuid)/openinghours")
        guard let response = try? await client.send(.get, url, auth: .bearer), response.isSuccessful,
              let items = response.jsonObject()?["items"] as? [[String: Any]], let first = items.first else { return nil }
        return (first["id"] as? String) ?? (first["id"] as? Int).map(String.init)
    }

    // MARK: Colleagues

    func getColleagues(user: User) async throws -> [Colleague] {
        let clientId = String(user.client.id)
        var colleagues: [Colleague] = []
        if user.hasPermission(.canViewColleagues) {
            for item in try await collect(path: "v2/clients/\(clientId)/users") {
                guard let id = item["id"] as? String, let name = item["name"] as? String else { continue }
                colleagues.append(Colleague(id: id, name: name))
            }
        }
        if user.hasPermission(.canViewVoipAccounts) {
            for item in try await collect(path: "v2/clients/\(clientId)/voip_accounts", query: ["filter_accounts": "without_connected_users"]) {
                guard item["status"] as? String == "active",
                      let name = item["description"] as? String else { continue }
                let id = (item["id"] as? String) ?? (item["id"] as? Int).map(String.init) ?? UUID().uuidString
                let number = (item["internal_number"] as? String) ?? (item["internal_number"] as? Int).map(String.init) ?? ""
                colleagues.append(Colleague(id: id, name: name, isUnconnectedVoipAccount: true, unconnectedNumber: number))
            }
        }
        return colleagues.filter { $0.id != user.uuid }
    }

    /// Follows VoIPGRID pagination (`{next, items}` or a plain list with a Link header), up to 20 pages.
    private func collect(path: String, query: [String: String?] = [:]) async throws -> [[String: Any]] {
        var items: [[String: Any]] = []
        var page = 1
        while page <= 20 {
            var q = query
            q["page"] = String(page)
            q["per_page"] = "500"
            let response = try await client.send(.get, url(path), query: q)
            if !response.isSuccessful {
                if page > 1 && response.status == 404 { break }
                throw HTTPError.status(response.status, response.bodyString)
            }
            var hasNext = false
            if let list = response.jsonArray() as? [[String: Any]] {
                items += list
                let link = (response.headers["Link"] as? String) ?? (response.headers["link"] as? String) ?? ""
                hasNext = link.contains("rel=\"next\"")
            } else if let json = response.jsonObject() {
                items += json["items"] as? [[String: Any]] ?? []
                hasNext = (json["next"] as? String).map { !$0.isEmpty } ?? false
            }
            if !hasNext { break }
            page += 1
        }
        return items
    }
}

/// Holodeck user-status service.
struct UserStatusAPI {
    private let client = HTTPClient.shared

    private func url(for user: User) -> URL {
        Brand.availabilityServiceURL.appendingPathComponent("clients/\(user.client.uuid)/users/\(user.uuid)/status")
    }

    func getStatus(user: User) async throws -> UserAvailabilityStatus {
        let response = try await client.send(.get, url(for: user), auth: .bearer, includeClientHeaders: false)
        if response.status == 404 { return .available }
        guard response.isSuccessful, let raw = response.jsonObject()?["status"] as? String else {
            throw HTTPError.status(response.status, response.bodyString)
        }
        return UserAvailabilityStatus(rawValue: raw) ?? .available
    }

    func setStatus(user: User, status: UserAvailabilityStatus) async -> Bool {
        let response = try? await client.send(.post, url(for: user), json: ["status": status.rawValue], auth: .bearer, includeClientHeaders: false)
        return response?.isSuccessful ?? false
    }
}

/// Holodeck contactbook service.
struct SharedContactsAPI {
    private let client = HTTPClient.shared

    private func url(clientUuid: String, suffix: String = "") -> URL {
        var u = Brand.sharedContactsURL.appendingPathComponent("clients/\(clientUuid)/contacts")
        if !suffix.isEmpty { u = u.appendingPathComponent(suffix) }
        return u
    }

    func list(clientUuid: String) async throws -> [SharedContact] {
        var contacts: [SharedContact] = []
        var page = 1
        while page <= 20 {
            let response = try await client.send(.get, url(clientUuid: clientUuid), query: ["page": String(page), "per_page": "500"], auth: .bearer)
            guard response.isSuccessful, let json = response.jsonObject() else {
                throw HTTPError.status(response.status, response.bodyString)
            }
            if let items = json["items"] {
                let data = try JSONSerialization.data(withJSONObject: items)
                contacts += try JSONDecoder().decode([SharedContact].self, from: data)
            }
            guard let next = json["next"] as? String, !next.isEmpty else { break }
            page += 1
        }
        return contacts.filter { $0.givenName != "__UNLINKED_VOIP_ACCOUNTS__" }
    }

    func create(clientUuid: String, contact: SharedContact) async -> Bool {
        let response = try? await client.send(.post, url(clientUuid: clientUuid), json: contact.requestBody, auth: .bearer)
        return response?.isSuccessful ?? false
    }

    func update(clientUuid: String, contact: SharedContact) async -> Bool {
        guard let id = contact.id else { return false }
        let response = try? await client.send(.put, url(clientUuid: clientUuid, suffix: id), json: contact.requestBody, auth: .bearer)
        return response?.isSuccessful ?? false
    }

    func delete(clientUuid: String, id: String) async -> Bool {
        let response = try? await client.send(.delete, url(clientUuid: clientUuid, suffix: id), auth: .bearer)
        return response?.isSuccessful ?? false
    }
}
