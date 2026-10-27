import Foundation
import UIKit

enum HTTPMethod: String { case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE", head = "HEAD" }

/// How the Authorization header is chosen for a request.
enum AuthStyle {
    /// VoIPGRID rule: legacy `Token email:token` unless the path contains a `v2` segment.
    case voipgridAuto
    case legacyToken
    case bearer
    case none
    case explicit(String)
}

struct HTTPResponse {
    let status: Int
    let data: Data
    let headers: [AnyHashable: Any]

    var isSuccessful: Bool { (200..<300).contains(status) }
    var bodyString: String { String(data: data, encoding: .utf8) ?? "" }

    func json() -> Any? { try? JSONSerialization.jsonObject(with: data) }
    func jsonObject() -> [String: Any]? { json() as? [String: Any] }
    func jsonArray() -> [Any]? { json() as? [Any] }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try HTTPClient.decoder.decode(T.self, from: data)
    }
}

enum HTTPError: Error, LocalizedError {
    case transport(Error)
    case status(Int, String)
    case decoding(Error)
    case noConnection

    var errorDescription: String? {
        switch self {
        case .transport(let e): return e.localizedDescription
        case .status(let code, let body): return "HTTP \(code): \(body.prefix(200))"
        case .decoding(let e): return "Decoding failed: \(e)"
        case .noConnection: return "No connection"
        }
    }
}

struct Credentials {
    let email: String
    let token: String
}

final class HTTPClient: NSObject, URLSessionTaskDelegate {
    static let shared = HTTPClient()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    /// Kept in sync by the session. Read from the networking path, which is not on the main actor.
    var credentials: Credentials? {
        get { credentialsLock.withLock { _credentials } }
        set { credentialsLock.withLock { _credentials = newValue } }
    }
    private var _credentials: Credentials?
    private let credentialsLock = NSLock()
    /// Called on a 401 so the session can log the user out.
    var onUnauthorized: (URL) -> Void = { _ in }
    /// Called on a 429 so the settings screen can show the rate-limit countdown.
    var onRateLimited: (URL) -> Void = { _ in }

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = false
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    /// VoIPGRID answers paths without a trailing slash with a 301, and URLSession drops the
    /// Authorization header when following it. Re-apply the original headers on same-host redirects.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let original = task.originalRequest, original.url?.host == request.url?.host else {
            completionHandler(request)
            return
        }
        var redirected = request
        for (key, value) in original.allHTTPHeaderFields ?? [:] where redirected.value(forHTTPHeaderField: key) == nil {
            redirected.setValue(value, forHTTPHeaderField: key)
        }
        if response.statusCode == 307 || response.statusCode == 308 {
            redirected.httpMethod = original.httpMethod
            redirected.httpBody = original.httpBody
        }
        completionHandler(redirected)
    }

    private lazy var clientHeaders: [String: String] = [
        "X-Client-Type": "mobile",
        "X-Client-Product": "vialer",
        "X-Client-Version": BuildInfo.version,
        "X-Client-OS": "ios",
        "X-Client-OS-Version": BuildInfo.osVersion,
        "X-Client-Brand": Brand.identifier,
    ]

    func send(
        _ method: HTTPMethod,
        _ url: URL,
        query: [String: String?] = [:],
        headers: [String: String] = [:],
        json body: Any? = nil,
        auth: AuthStyle = .voipgridAuto,
        includeClientHeaders: Bool = true
    ) async throws -> HTTPResponse {
        var finalURL = url
        if !query.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            var items = components.queryItems ?? []
            for (key, value) in query {
                guard let value else { continue }
                items.append(URLQueryItem(name: key, value: value))
            }
            components.queryItems = items
            finalURL = components.url ?? url
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if includeClientHeaders {
            clientHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        }
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        if request.value(forHTTPHeaderField: "Authorization") == nil,
           let authHeader = authorizationHeader(for: auth, url: finalURL) {
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            if status == 401 { onUnauthorized(finalURL) }
            if status == 429 {
                AppLog.warning("Rate limited: \(finalURL)")
                Metrics.track("api-request-rate-limited", ["url": finalURL.path])
                onRateLimited(finalURL)
            }
            return HTTPResponse(status: status, data: data, headers: http?.allHeaderFields ?? [:])
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw HTTPError.noConnection
        } catch {
            throw HTTPError.transport(error)
        }
    }

    private func authorizationHeader(for style: AuthStyle, url: URL) -> String? {
        switch style {
        case .none:
            return nil
        case .explicit(let value):
            return value
        case .bearer:
            guard let c = credentials else { return nil }
            return "Bearer \(c.token)"
        case .legacyToken:
            guard let c = credentials else { return nil }
            return "Token \(c.email):\(c.token)"
        case .voipgridAuto:
            guard let c = credentials else { return nil }
            let isV2 = url.pathComponents.contains("v2")
            return isV2 ? "Bearer \(c.token)" : "Token \(c.email):\(c.token)"
        }
    }
}
