import Foundation
import PushKit
import UIKit

struct CurrentCallInfo {
    let callId: String
    let correlationId: String
    let pushReceivedTime: String
}

/// Push registration and incoming-call responses against the Callwaker middleware.
/// Ported from the Flutter app's native `Middleware.swift`.
final class CallwakerMiddleware: Middleware {
    private let store = LocalStore.shared
    private static let secondsBeforeRejected = 8

    /// Kept in sync by the app container; PushKit and URLSession callbacks may arrive off the main thread.
    var currentUser: User? {
        get { stateLock.withLock { _currentUser } }
        set { stateLock.withLock { _currentUser = newValue } }
    }
    var isVoipEnabled: Bool {
        get { stateLock.withLock { _isVoipEnabled } }
        set { stateLock.withLock { _isVoipEnabled = newValue } }
    }
    private var _currentUser: User?
    private var _isVoipEnabled = true
    private let stateLock = NSLock()
    var onLoggedInSomewhereElse: () -> Void = {}

    var currentCallInfo: CurrentCallInfo?

    private let registrationLock = NSLock()
    private var isRegistering = false

    var baseURL: URL { Brand.callwakerURL }

    // MARK: Middleware (phone lib)

    func tokenReceived(token: String) {
        Metrics.track("push-token-received", ["push-token": mask(token)])
        store.setString(token, for: .pushToken)
        register()
    }

    func inspect(payload: PKPushPayload, type: PKPushType) {
        Metrics.track("middleware-notification-received", payload.trackingProperties.merging([
            "seconds_from_call_to_received": String(payload.secondsSincePushWasSent),
            "middleware_url": baseURL.absoluteString,
            "service": "callwaker",
        ]) { a, _ in a })
    }

    func respond(payload: PKPushPayload, available: Bool, reason: UnavailableReason?) {
        let callId = payload.callId
        guard let responseURL = URL(string: payload.responseUrl) else {
            AppLog.error("Middleware respond: push payload has no response_api")
            return
        }
        AppLog.info("Middleware respond: call=\(callId) available=\(available)")
        if payload.secondsSincePushWasSent > Self.secondsBeforeRejected {
            AppLog.warning("Push response time is \(payload.secondsSincePushWasSent)s, likely too late for this call")
        }

        let unavailableReason: String
        switch reason {
        case .inCall: unavailableReason = "IN_CALL"
        case .unableToRegister: unavailableReason = "UNABLE_TO_REGISTER"
        case nil: unavailableReason = ""
        }

        var request = URLRequest(url: responseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["call_id": callId, "available": available])

        if available { currentCallInfo = payload.toCurrentCallInfo() }

        URLSession.shared.dataTask(with: request) { _, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode
            Metrics.track("middleware-responded", payload.trackingProperties.merging([
                "middleware_response": error?.localizedDescription ?? String(status ?? 0),
                "available": String(available),
                "unavailable_reason": unavailableReason,
                "seconds_from_call_to_responded": String(payload.secondsSincePushWasSent),
                "middleware_url": self.baseURL.absoluteString,
                "service": "callwaker",
            ]) { a, _ in a })
            if let error {
                AppLog.error("Middleware respond failed: \(error)")
            } else if let status, (200..<300).contains(status) {
                AppLog.info("Middleware respond success: \(callId)")
            } else {
                AppLog.error("Middleware respond failed: response code \(String(describing: status))")
            }
        }.resume()
    }

    // MARK: Registration

    func register() {
        guard let user = currentUser else {
            AppLog.info("Registration cancelled: no user")
            return
        }
        if store.bool(.isLoggedInSomewhereElse) {
            AppLog.info("Registration cancelled: user has logged in elsewhere")
            unregister()
            return
        }
        guard let sipUserId = user.appAccount?.sipUserId, let appAccountId = Int(sipUserId) else {
            AppLog.info("Registration cancelled: no SIP user id")
            return
        }
        guard let token = store.string(.pushToken) else {
            AppLog.info("Registration cancelled: no push token")
            return
        }
        guard isVoipEnabled else {
            AppLog.info("Registration cancelled: VoIP not enabled")
            return
        }
        if store.string(.installationId) == nil {
            store.setString(UUID().uuidString.lowercased(), for: .installationId)
        }
        registrationLock.lock()
        if isRegistering {
            registrationLock.unlock()
            AppLog.info("Registration already in progress, skipping")
            return
        }
        isRegistering = true
        registrationLock.unlock()

        sendRegistration(token: token, apiToken: user.token, appAccountId: appAccountId, registrationToken: store.string(.middlewareRegistrationToken))
    }

    private func endRegistration() {
        registrationLock.lock()
        isRegistering = false
        registrationLock.unlock()
    }

    private func sendRegistration(token: String, apiToken: String, appAccountId: Int, registrationToken: String?) {
        let url = baseURL.appendingPathComponent(registrationToken != nil ? "refresh_register" : "register")
        AppLog.info("Registering to middleware: \(url)")

        var data: [String: Any] = [
            "platform": "ios",
            "app_id": Brand.bundleId,
            "app_account_id": appAccountId,
            "push_token": token,
            "os_version": BuildInfo.osVersion,
            "app_version": BuildInfo.version,
            "is_sandbox": BuildInfo.isSandboxPush,
            "installation_id": store.string(.installationId) ?? "",
        ]
        if let registrationToken { data["registration_token"] = registrationToken }

        var request = makeRequest(url: url, apiToken: apiToken)
        request.httpBody = try? JSONSerialization.data(withJSONObject: data)

        URLSession.shared.dataTask(with: request) { [weak self] body, response, error in
            guard let self else { return }
            let status = (response as? HTTPURLResponse)?.statusCode
            let ok = status.map { (200..<300).contains($0) } ?? false
            if ok {
                if let body, let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                   let newToken = json["registration_token"] as? String {
                    self.store.setString(newToken, for: .middlewareRegistrationToken)
                }
                AppLog.info("Middleware registration successful")
                self.endRegistration()
            } else if registrationToken != nil, status == 409 {
                AppLog.warning("Refresh returned 409: account registered on another device, logging out")
                self.store.setBool(true, for: .isLoggedInSomewhereElse)
                self.endRegistration()
                DispatchQueue.main.async { self.onLoggedInSomewhereElse() }
            } else if registrationToken != nil, [403, 404].contains(status ?? 0) {
                AppLog.warning("Refresh failed with \(String(describing: status)), falling back to full registration")
                self.store.remove(.middlewareRegistrationToken)
                self.sendRegistration(token: token, apiToken: apiToken, appAccountId: appAccountId, registrationToken: nil)
            } else {
                Metrics.track("middleware-registration-failed", [
                    "status_code": status.map(String.init) ?? "",
                    "error": error?.localizedDescription ?? "",
                    "middleware_url": self.baseURL.absoluteString,
                    "service": "callwaker",
                ])
                AppLog.error("Middleware registration failed: \(String(describing: status)) \(error?.localizedDescription ?? "")")
                self.endRegistration()
            }
        }.resume()
    }

    func unregister(completion: (() -> Void)? = nil) {
        guard let user = currentUser,
              let sipUserId = user.appAccount?.sipUserId, let appAccountId = Int(sipUserId),
              let installationId = store.string(.installationId),
              let registrationToken = store.string(.middlewareRegistrationToken) else {
            AppLog.info("Skipping unregister: no active registration")
            completion?()
            return
        }
        let url = baseURL.appendingPathComponent("unregister")
        AppLog.info("Unregistering from middleware: \(url)")
        var request = makeRequest(url: url, apiToken: user.token)
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "app_account_id": appAccountId,
            "installation_id": installationId,
            "registration_token": registrationToken,
        ])
        URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode
            if let status, (200..<300).contains(status) {
                self?.store.remove(.middlewareRegistrationToken)
                AppLog.info("Unregister successful")
            } else {
                AppLog.warning("Unregister failed: \(String(describing: status))")
            }
            completion?()
        }.resume()
    }

    private func makeRequest(url: URL, apiToken: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func mask(_ token: String) -> String {
        guard token.count > 6 else { return String(repeating: "*", count: token.count) }
        return String(repeating: "*", count: token.count - 6) + token.suffix(6)
    }
}

extension PKPushPayload {
    var callId: String { dictionaryPayload["call_id"] as? String ?? "" }
    var correlationId: String { dictionaryPayload["vg_cid"] as? String ?? "" }
    var messageStartTime: Int { Int(dictionaryPayload["message_start_time"] as? Double ?? 0) }
    var responseUrl: String { dictionaryPayload["response_api"] as? String ?? "" }
    var secondsSincePushWasSent: Int { Int(Date().timeIntervalSince1970) - messageStartTime }

    var trackingProperties: [String: Any] {
        [
            "call_id": callId,
            "correlation_id": correlationId,
            "message_start_time": String(messageStartTime),
            "push_sent_time": String(messageStartTime),
            "response_url": responseUrl,
        ]
    }

    func toCurrentCallInfo() -> CurrentCallInfo {
        CurrentCallInfo(callId: callId, correlationId: correlationId, pushReceivedTime: String(Int(Date().timeIntervalSince1970) * 1000))
    }
}
