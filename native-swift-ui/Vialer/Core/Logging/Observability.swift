import Foundation
import Network
import os
import Segment
import Sentry

/// Console logging plus an in-memory buffer shown on the Logs page; every line is also offered to
/// `RemoteLogging`, which forwards it when the user enabled remote logging.
enum AppLog {
    private static let logger = os.Logger(subsystem: Brand.bundleId, category: "app")
    private static let lock = NSLock()
    private(set) static var buffer: [String] = []
    private static let maxBufferedLines = 2000

    static func info(_ message: String) { write("INFO", message) }
    static func warning(_ message: String) { write("WARNING", message) }
    static func error(_ message: String) { write("ERROR", message) }

    private static func write(_ level: String, _ message: String) {
        let line = "[\(Date().formatted(date: .omitted, time: .standard))] \(level) \(message)"
        logger.log("\(line, privacy: .public)")
        #if DEBUG
        // Lets `devicectl ... launch --console` capture the log from a device without root.
        print(line)
        #endif
        lock.lock()
        buffer.append(line)
        if buffer.count > maxBufferedLines { buffer.removeFirst(buffer.count - maxBufferedLines) }
        lock.unlock()
        RemoteLogging.shared.send(level: level, message: message)
    }
}

/// Strips user-identifiable data before a line leaves the device; the same rules the Flutter app
/// applied to both Dart and native logs.
enum LogAnonymizer {
    private static let rules: [(NSRegularExpression, String)] = [
        (#"\+(9[976]\d|8[987530]\d|6[987]\d|5[90]\d|42\d|3[875]\d|2[98654321]\d|9[8543210]|8[6421]|6[6543210]|5[87654321]|4[987654310]|3[9643210]|2[70]|7|1)\d{1,14}$"#,
         "[REDACTED PHONE NUMBER]"),
        (#"(?:[a-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[a-z0-9!#$%&'*+/=?^_`{|}~-]+)*|"(?:[\x01-\x08\x0b\x0c\x0e-\x1f\x21\x23-\x5b\x5d-\x7f]|\\[\x01-\x09\x0b\x0c\x0e-\x7f])*")@(?:(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]*[a-z0-9])?|\[(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?|[a-z0-9-]*[a-z0-9]:(?:[\x01-\x08\x0b\x0c\x0e-\x1f\x21-\x5a\x53-\x7f]|\\[\x01-\x09\x0b\x0c\x0e-\x7f])+)\])"#,
         "[REDACTED EMAIL]"),
        (#"sip:\+?\d+"#, "sip:[REDACTED]"),
        (#"To:(.+?)>"#, "To: [REDACTED]"),
        (#"From:(.+?)>"#, "From: [REDACTED]"),
        (#"Contact:(.+?)>"#, "Contact: [REDACTED]"),
        (#"username=(.+?)&"#, "username=[REDACTED]"),
        (#"nonce="(.+?)""#, "nonce=\"[REDACTED]\""),
        (#""caller_id" = (.+?);"#, "\"caller_id\" = [REDACTED];"),
        (#"Digest username="(.+?)""#, "Digest username=\"[REDACTED]\""),
    ].compactMap { pattern, replacement in
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return (regex, NSRegularExpression.escapedTemplate(for: replacement))
    }

    static func apply(to message: String) -> String {
        rules.reduce(message) { result, rule in
            rule.0.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: (result as NSString).length), withTemplate: rule.1)
        }
    }
}

/// Logentries (Rapid7 InsightOps) remote logging over a plain TLS socket, one `<token> <line>` per
/// line, as the Flutter app did. Reconnects a limited number of times and then gives up silently.
final class RemoteLogging {
    static let shared = RemoteLogging()

    private let queue = DispatchQueue(label: "remote-logging")
    private let token = Env.logentriesIOSToken
    private var connection: NWConnection?
    private var isConnected = false
    private var failedConnections = 0
    private static let maxReconnects = 10

    var userIdentifier: String?

    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            queue.async { self.isEnabled ? self.connect() : self.disconnect() }
        }
    }

    var isAvailable: Bool { !(token ?? "").isEmpty }

    func send(level: String, message: String) {
        guard isEnabled, let token, !token.isEmpty else { return }
        let user = userIdentifier.map { "[\($0)]" } ?? ""
        let line = "[\(Date())] [\(BuildInfo.version)] \(level) \(user) app: \(LogAnonymizer.apply(to: message))"
        queue.async { self.write("\(token) \(line)\n") }
    }

    private func write(_ text: String) {
        if !isConnected {
            guard failedConnections < Self.maxReconnects, connection == nil else { return }
            connect()
            return
        }
        connection?.send(content: Data(text.utf8), completion: .contentProcessed { [weak self] error in
            if let error { self?.handleFailure(error) }
        })
    }

    private func connect() {
        guard connection == nil, isAvailable else { return }
        let connection = NWConnection(host: "data.logentries.com", port: 443, using: .tls)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                isConnected = true
                failedConnections = 0
            case .failed(let error):
                handleFailure(error)
            case .cancelled:
                isConnected = false
            default:
                break
            }
        }
        self.connection = connection
        connection.start(queue: queue)
    }

    private func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
    }

    private func handleFailure(_ error: Error) {
        isConnected = false
        connection?.cancel()
        connection = nil
        failedConnections += 1
        if failedConnections == Self.maxReconnects {
            os.Logger(subsystem: Brand.bundleId, category: "remote-logging")
                .error("Can not connect to Logentries, not trying again: \(error)")
        }
    }
}

// MARK: - Metrics

protocol MetricsTracking {
    func track(_ event: String, _ properties: [String: Any])
    func identify(_ userId: String, traits: [String: Any])
}

struct ConsoleMetrics: MetricsTracking {
    func track(_ event: String, _ properties: [String: Any]) {
        AppLog.info("metric: \(event) \(properties)")
    }

    func identify(_ userId: String, traits: [String: Any]) {
        AppLog.info("metric identify: \(userId)")
    }
}

/// Segment with the IP and device identifiers blanked, matching the Flutter app's context.
struct SegmentMetrics: MetricsTracking {
    private let analytics: Segment.Analytics

    init(writeKey: String) {
        let configuration = Segment.Configuration(writeKey: writeKey)
            .trackApplicationLifecycleEvents(true)
            .flushAt(20)
        analytics = Segment.Analytics(configuration: configuration)
        analytics.add(plugin: AnonymizingPlugin())
    }

    func track(_ event: String, _ properties: [String: Any]) {
        analytics.track(name: event, properties: properties)
    }

    func identify(_ userId: String, traits: [String: Any]) {
        analytics.identify(userId: userId, traits: traits)
    }

    private final class AnonymizingPlugin: Segment.Plugin {
        let type = Segment.PluginType.enrichment
        weak var analytics: Segment.Analytics?

        func execute<T: Segment.RawEvent>(event: T?) -> T? {
            guard var event, var context = event.context?.dictionaryValue else { return event }
            context["ip"] = "0.0.0.0"
            var device = context["device"] as? [String: Any] ?? [:]
            device["id"] = ""
            device["advertisingId"] = ""
            device["token"] = ""
            context["device"] = device
            event.context = try? Segment.JSON(context)
            return event
        }
    }
}

enum Metrics {
    /// Events only reach Segment in release builds, as in the Flutter app.
    static var tracker: MetricsTracking = {
        #if DEBUG
        return ConsoleMetrics()
        #else
        if let key = Env.segmentIOSKey, !key.isEmpty { return SegmentMetrics(writeKey: key) }
        return ConsoleMetrics()
        #endif
    }()

    static func track(_ event: String, _ properties: [String: Any] = [:]) {
        assert(event == event.lowercased() && !event.contains(" ") && !event.contains("_"), "Event name \(event) not in param-case")
        tracker.track(event, properties)
    }

    static func identify(_ userId: String, traits: [String: Any] = [:]) {
        tracker.identify(userId, traits: traits)
    }
}

// MARK: - Error tracking

enum ErrorTracking {
    private(set) static var isEnabled = false

    /// Starts Sentry when a DSN is configured; call once, before anything else runs.
    static func start() {
        guard let dsn = Env.sentryDSN, !dsn.isEmpty else { return }
        SentrySDK.start { options in
            options.dsn = dsn
            options.sampleRate = 0.5
            options.enableCaptureFailedRequests = false
            options.releaseName = "\(Brand.bundleId)@\(BuildInfo.version)+\(BuildInfo.buildNumber)"
            options.environment = Env.isProduction ? "production" : "development"
            options.beforeSend = { event in
                AppLog.error("Error [\(event.eventId.sentryIdString)]: \(event.message?.formatted ?? event.exceptions?.first?.value ?? "unknown")")
                return event
            }
        }
        isEnabled = true
    }

    static func setUser(id: String?) {
        guard isEnabled else { return }
        SentrySDK.setUser(id.map { Sentry.User(userId: $0) })
    }

    static func capture(_ error: Error, context: String = "") {
        AppLog.error("\(context) \(error)")
        guard isEnabled else { return }
        SentrySDK.capture(error: error) { scope in
            if !context.isEmpty { scope.setTag(value: context, key: "context") }
        }
    }
}
