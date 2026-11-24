import flutter_phone_lib
import shared_secure_storage
import PushKit
import Alamofire

public class Middleware: NSObject, NativeMiddleware, MiddlewareRegistrar {
    private let logger: Logger
    private let segment: Segment

    private let flutterSharedPreferences = FlutterSharedPreferences()
    private let secureStorage = SharedSecureStorage.shared
    public var baseUrl: String {
        get {
            // The hardcoded callwaker URL, picking the environment based on the
            // existing per-flavor/per-user middleware URL.
            let environment = flutterSharedPreferences.middlewareUrl.contains("staging")
                ? "staging"
                : "production"
            return "https://api.eu-\(environment).holodeck.voys.nl/callwaker"
        }
    }

    public var currentCallInfo: CurrentCallInfo?

    private static let secondsBeforeRejected = 8

    /// Guards against overlapping registration requests. Several triggers
    /// (tokenReceived, StartVoip, the use-voip settings listener, user-data
    /// refresh) can call register() at the same time; at first login the stored
    /// registration token is still nil, so each would POST /register with the
    /// same push token and race callwaker's one-active-registration unique index.
    /// Coalescing them into a single in-flight request avoids that.
    private let registrationLock = NSLock()
    private var isRegistering = false

    private var middlewareCredentials: MiddlewareCredentials {
        get {
            MiddlewareCredentials(
                // Versions up to 7.75.0 stored the token in the user, it's moved once Flutter
                // starts. Remove the fallback once almost all users have upgraded from 7.75.0.
                loginToken: (try? secureStorage.read(secureStorageApiTokenKey))
                    ?? flutterSharedPreferences.systemUser?["token"] as? String
                    ?? "",
                sipUserId: (flutterSharedPreferences.systemUser?["voip"] as? [String : Any])?["appaccount_account_id"] as? String ?? ""
            )
        }
    }

    init(logger: Logger, segment: Segment) {
        self.logger = logger
        self.segment = segment
    }

    public func tokenReceived(token: String) {
        segment.track(event: "push-token-received", properties: [
            "push-token": maskPushToken(token)
        ])

        try? register(token: token)
    }

    /// Atomically claims the in-flight registration slot, returning false if a
    /// registration is already running.
    private func beginRegistrationIfIdle() -> Bool {
        registrationLock.lock()
        defer { registrationLock.unlock() }
        if isRegistering { return false }
        isRegistering = true
        return true
    }

    private func endRegistration() {
        registrationLock.lock()
        isRegistering = false
        registrationLock.unlock()
    }

    func register(token: String) throws {
        flutterSharedPreferences.pushToken = token

        guard let appAccountId = Int(middlewareCredentials.sipUserId) else {
            logger.writeLog("Registration cancelled: sipUserId is not a number")
            return
        }

        guard !middlewareCredentials.loginToken.isEmpty else {
            logger.writeLog("Registration cancelled: there is no API token")
            return
        }

        // Generate a stable installation id on first registration if one isn't
        // set yet; it is persisted so Dart can read it back when unregistering.
        if flutterSharedPreferences.installationId == nil {
            flutterSharedPreferences.installationId = UUID().uuidString.lowercased()
        }

        // Coalesce overlapping triggers: if a registration is already in flight,
        // skip this one rather than firing a second, racing /register.
        guard beginRegistrationIfIdle() else {
            logger.writeLog("Registration already in progress, skipping duplicate request")
            return
        }

        sendRegistration(
            token: token,
            apiToken: middlewareCredentials.loginToken,
            appAccountId: appAccountId,
            registrationToken: flutterSharedPreferences.middlewareRegistrationToken
        )
    }

    private func sendRegistration(
        token: String,
        apiToken: String,
        appAccountId: Int,
        registrationToken: String?
    ) {
        let sandbox = Bundle.main.infoDictionary?["Sandbox"] as? String

        // A registration token proves a prior registration, allowing the
        // cheaper refresh endpoint to be used instead.
        let urlString = registrationToken != nil
            ? "\(baseUrl)/refresh_register"
            : "\(baseUrl)/register"

        logger.writeLog("Registering to middleware: \(urlString)")

        var data: [String : Any] = [
            "platform": "ios",
            "app_id": Bundle.main.bundleIdentifier ?? "",
            "app_account_id": appAccountId,
            "push_token": token,
            "os_version": UIDevice.current.systemVersion,
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as Any,
            "is_sandbox": (sandbox?.lowercased() == "true"),
            "installation_id": flutterSharedPreferences.installationId ?? ""
        ]
        if let registrationToken = registrationToken {
            data["registration_token"] = registrationToken
        }

        var request = createMiddlewareRequest(token: apiToken, url: urlString)
        request.httpBody = try! JSONSerialization.data(withJSONObject: data)

        AF.request(request).responseData { [weak self] (response) -> Void in
            guard let self = self else { return }
            let statusCode = response.response?.statusCode
            let isSuccessful = statusCode.map { (200..<300).contains($0) } ?? false

            if isSuccessful {
                if let responseData = response.data,
                   let json = try? JSONSerialization.jsonObject(with: responseData) as? [String : Any],
                   let newRegistrationToken = json["registration_token"] as? String {
                    self.flutterSharedPreferences.middlewareRegistrationToken = newRegistrationToken
                }
                self.logger.writeLog("Registration successful")
                self.endRegistration()
            } else if registrationToken != nil, statusCode == 409 {
                // 409 = account registered on another device; log out.
                self.logger.writeLog("Refresh returned 409: account registered on another device, logging out")
                self.flutterSharedPreferences.isLoggedInSomewhereElse = true
                self.endRegistration()
            } else if registrationToken != nil, [403, 404].contains(statusCode ?? 0) {
                // The stored registration token is no longer valid, fall back
                // to a full registration. Keep the in-flight slot held: the
                // fallback is the same registration and releases it.
                self.logger.writeLog("Refresh failed with status code: \(String(describing: statusCode)), falling back to full registration")
                self.flutterSharedPreferences.middlewareRegistrationToken = nil
                self.sendRegistration(
                    token: token,
                    apiToken: apiToken,
                    appAccountId: appAccountId,
                    registrationToken: nil
                )
            } else {
                self.trackRegistrationFailed(statusCode: statusCode, error: response.error?.errorDescription)
                self.logger.writeLog("Registration failed: response code was \(String(describing: statusCode))")
                self.endRegistration()
            }
        }
    }

    func unregister(appAccountId: Int64) throws {
        guard let installationId = flutterSharedPreferences.installationId,
              let registrationToken = flutterSharedPreferences.middlewareRegistrationToken else {
            logger.writeLog("Skipping unregister: no active registration")
            return
        }

        guard !middlewareCredentials.loginToken.isEmpty else {
            logger.writeLog("Skipping unregister: there is no API token")
            return
        }

        let urlString = "\(baseUrl)/unregister"
        logger.writeLog("Unregistering from middleware: \(urlString)")

        let data: [String : Any] = [
            "app_account_id": appAccountId,
            "installation_id": installationId,
            "registration_token": registrationToken,
        ]

        var request = createMiddlewareRequest(token: middlewareCredentials.loginToken, url: urlString)
        request.httpBody = try! JSONSerialization.data(withJSONObject: data)

        AF.request(request).response { [weak self] (response) -> Void in
            guard let self = self else { return }
            let statusCode = response.response?.statusCode
            let isSuccessful = statusCode.map { (200..<300).contains($0) } ?? false
            if isSuccessful {
                self.flutterSharedPreferences.middlewareRegistrationToken = nil
                self.logger.writeLog("Unregister successful")
            } else {
                self.logger.writeLog("Unregister failed: response code was \(String(describing: statusCode))")
            }
        }
    }

    public func respond(payload: PKPushPayload, available: Bool, reason: NativeMiddlewareUnavailableReason?) {
        let payloadDictionary = payload.dictionaryPayload as NSDictionary
        let callId = payload.callId
        let correlationId = payloadDictionary.value(forKey: "vg_cid")
        let responseUrl = payload.responseUrl
        let pushResponseTime = payload.secondsSincePushWasSent

        logger.writeLog("Middleware Respond: Attempting for call=\(callId), correlationId=\(String(describing: correlationId)), available=\(available)")

        if pushResponseTime > Middleware.secondsBeforeRejected {
            logger.writeLog("The response time is $pushResponseTime, it is likely we are too late for this call.")
        }

        let data: [String : Any] = [
            "call_id": callId,
            "available": available,
        ]

        var request = URLRequest(url: URL(string: responseUrl)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try! JSONSerialization.data(withJSONObject: data)

        let unavailableReason: String = {
            switch reason {
                case .inCall: return "IN_CALL"
                case .unableToRegister: return "UNABLE_TO_REGISTER"
                default: return ""
            }
        }()
        
        let track: (_ middlewareResponse: String) -> Void = { (response) in
            self.trackNotificationResult(
                payload: payload,
                middlewareResponse: response,
                available: available,
                reason: unavailableReason,
                responseTime: payload.secondsSincePushWasSent
            )
        }

        AF.request(request).response { (response) -> Void in
            let statusCode = response.response?.statusCode

            if response.error != nil {
                self.logger.writeLog("Middleware respond failed: \(response.error!)")
                track(response.error?.errorDescription ?? "error")
                self.trackResponseFailed(payload: payload, statusCode: statusCode, error: response.error?.errorDescription, available: available, reason: unavailableReason)
                return
            }

            track(String(statusCode ?? 0))

            let isSuccessful = statusCode.map { (200..<300).contains($0) } ?? false
            if isSuccessful {
                self.logger.writeLog("Middleware respond success: \(String(describing: callId))")
            } else {
                self.trackResponseFailed(payload: payload, statusCode: statusCode, error: nil, available: available, reason: unavailableReason)
                self.logger.writeLog("Middleware respond failed: response code was \(String(describing: statusCode))")
            }
        }

        if available {
            currentCallInfo = payload.toCurrentCallInfo()
        }
    }

    public func inspect(payload: PKPushPayload, type: PKPushType) {
        segment.track(event: "middleware-notification-received", properties: payload.withTrackingProperties(properties: [
            "seconds_from_call_to_received" : String(payload.secondsSincePushWasSent),
            "middleware_url" : baseUrl,
            "service" : "callwaker",
        ]))
    }

    public func extractCallDetail(from payload: PKPushPayload) -> CallDetail {
        let phoneNumber = payload.dictionaryPayload["phonenumber"] as? String ?? ""
        let callerId = payload.dictionaryPayload["caller_id"] as? String ?? ""

        return CallDetail(phoneNumber: phoneNumber, callId: callerId)
    }

    private func trackRegistrationFailed(statusCode: Int?, error: String?) {
        segment.track(event: "middleware-registration-failed", properties: [
            "status_code" : statusCode.map { String($0) } ?? "",
            "error" : error ?? "",
            "middleware_url" : baseUrl,
            "service" : "callwaker",
        ])
    }

    private func trackResponseFailed(payload: PKPushPayload, statusCode: Int?, error: String?, available: Bool, reason: String) {
        segment.track(event: "middleware-response-failed", properties: payload.withTrackingProperties(properties: [
            "status_code" : statusCode.map { String($0) } ?? "",
            "error" : error ?? "",
            "available" : String(available),
            "unavailable_reason" : reason,
            "middleware_url" : baseUrl,
            "service" : "callwaker",
        ]))
    }

    private func trackNotificationResult(payload: PKPushPayload, middlewareResponse: String, available: Bool, reason: String, responseTime: Int) {
        segment.track(event: "middleware-responded", properties: payload.withTrackingProperties(properties: [
            "middleware_response" : middlewareResponse,
            "available" : String(available),
            "unavailable_reason" : reason,
            "seconds_from_call_to_responded" : String(responseTime),
            "middleware_url" : baseUrl,
            "service" : "callwaker",
        ]))
    }

    private func createMiddlewareRequest(token: String, url: String) -> URLRequest {
        var request = URLRequest(url: NSURL(string: url)! as URL)

        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        return request
    }

    private func maskPushToken(_ token: String) -> String {
        guard token.count > 6 else { return String(repeating: "*", count: token.count) }
        let maskedPortion = String(repeating: "*", count: token.count - 6)
        let lastSix = String(token.suffix(6))
        return maskedPortion + lastSix
    }
}

private struct MiddlewareCredentials {
    let loginToken: String
    let sipUserId: String
}

extension PKPushPayload {

    var callId: String {
        dictionaryPayload["call_id"] as? String ?? ""
    }

    var correlationId: String {
        dictionaryPayload["vg_cid"] as? String ?? ""
    }

    var messageStartTime: Int {
        Int(dictionaryPayload["message_start_time"] as? Double ?? 0.0)
    }

    var isCall: Bool {
        (dictionaryPayload["type"] as? String ?? "") == "call"
    }

    var responseUrl: String {
        dictionaryPayload["response_api"] as! String
    }

    var trackingProperties: [String : String] {
        [
            "call_id" : callId,
            "correlation_id" : correlationId,
            "message_start_time" : String(messageStartTime),
            "push_sent_time" : String(messageStartTime),
            "response_url": responseUrl,
        ]
    }

    func withTrackingProperties(properties: [String : String]) -> [String : String] {
        return trackingProperties.merging(properties) { (current,_) in current }
    }

    var secondsSincePushWasSent: Int {
        Int((Date().timeIntervalSince1970)) - messageStartTime
    }

    func toCurrentCallInfo() -> CurrentCallInfo {
        return CurrentCallInfo(
            callId: callId,
            correlationId: correlationId,
            pushReceivedTime: String(Int(Date().timeIntervalSince1970) * 1000)
        )
    }
}

public struct CurrentCallInfo {
    public let callId: String
    public let correlationId: String
    public let pushReceivedTime: String
}
