import Foundation

/// A small RES protocol client (https://resgate.io) over URLSessionWebSocketTask.
/// Keeps a model cache so change events can be delivered as full models.
final class ResClient {
    enum Event {
        case connected
        case disconnected(Error?)
        case modelChanged(rid: String, model: [String: Any])
        case collectionAdded(rid: String, itemRid: String)
        case collectionRemoved(rid: String, itemRid: String)
    }

    private let url: URL
    private var task: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private var nextId = 1
    private var pending: [Int: (Result<[String: Any], Error>) -> Void] = [:]
    private let lock = NSLock()
    private(set) var models: [String: [String: Any]] = [:]
    private(set) var collections: [String: [String]] = [:]
    var onEvent: (Event) -> Void = { _ in }
    private(set) var isConnected = false

    init(url: URL) {
        self.url = url
    }

    func connect() {
        guard task == nil else { return }
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        isConnected = true
        receiveLoop()
        onEvent(.connected)
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
        lock.lock()
        let waiting = pending
        pending.removeAll()
        models.removeAll()
        collections.removeAll()
        lock.unlock()
        waiting.values.forEach { $0(.failure(ResError.disconnected)) }
    }

    enum ResError: Error { case disconnected, remote(String), invalid }

    // MARK: Requests

    /// Announces the protocol version. Without this Resgate treats the client as legacy and
    /// replaces every data value (nested objects such as `destination`) with the string "[Data]".
    func handshake() async throws {
        _ = try await request(method: "version", params: ["protocol": "1.2.1"])
    }

    func auth(token: String) async throws {
        _ = try await request(method: "auth.usertoken.login", params: ["token": token])
    }

    func subscribe(_ rid: String) async throws {
        let result = try await request(method: "subscribe.\(rid)", params: nil)
        ingest(result)
    }

    func get(_ rid: String) async throws {
        let result = try await request(method: "get.\(rid)", params: nil)
        ingest(result)
    }

    /// Models currently cached for a rid: the model itself, or the models in the collection.
    /// Nested resource references (`{"rid": "..."}`) are replaced by the referenced model.
    func items(for rid: String) -> [(rid: String, model: [String: Any])] {
        lock.lock(); defer { lock.unlock() }
        if let model = models[rid] { return [(rid, resolved(model))] }
        if let refs = collections[rid] {
            return refs.compactMap { ref in models[ref].map { (ref, resolved($0)) } }
        }
        return []
    }

    /// The rid of the model that references `rid` as a nested resource, if any.
    func parent(of rid: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return models.first { _, model in
            model.values.contains { ($0 as? [String: Any])?["rid"] as? String == rid }
        }?.key
    }

    /// Must be called with the lock held.
    private func resolved(_ model: [String: Any]) -> [String: Any] {
        model.mapValues { value in
            if let ref = (value as? [String: Any])?["rid"] as? String, let nested = models[ref] { return nested }
            return value
        }
    }

    private func request(method: String, params: [String: Any]?) async throws -> [String: Any] {
        guard let task else { throw ResError.disconnected }
        let id = lock.withLock { () -> Int in
            let id = nextId
            nextId += 1
            return id
        }
        var message: [String: Any] = ["id": id, "method": method]
        if let params { message["params"] = params }
        let data = try JSONSerialization.data(withJSONObject: message)
        guard let text = String(data: data, encoding: .utf8) else { throw ResError.invalid }

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            pending[id] = { continuation.resume(with: $0) }
            lock.unlock()
            task.send(.string(text)) { [weak self] error in
                guard let error, let self else { return }
                self.lock.lock()
                let callback = self.pending.removeValue(forKey: id)
                self.lock.unlock()
                callback?(.failure(error))
            }
        }
    }

    // MARK: Receiving

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.handleDisconnect(error)
            case .success(let message):
                switch message {
                case .string(let text): self.handle(text: text)
                case .data(let data): self.handle(text: String(data: data, encoding: .utf8) ?? "")
                @unknown default: break
                }
                self.receiveLoop()
            }
        }
    }

    private func handleDisconnect(_ error: Error?) {
        guard task != nil else { return }
        task = nil
        isConnected = false
        lock.lock()
        let waiting = pending
        pending.removeAll()
        lock.unlock()
        waiting.values.forEach { $0(.failure(error ?? ResError.disconnected)) }
        onEvent(.disconnected(error))
    }

    private func handle(text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let id = json["id"] as? Int {
            lock.lock()
            let callback = pending.removeValue(forKey: id)
            lock.unlock()
            if let error = json["error"] as? [String: Any] {
                callback?(.failure(ResError.remote(error["message"] as? String ?? "unknown")))
            } else {
                callback?(.success(json["result"] as? [String: Any] ?? [:]))
            }
            return
        }

        guard let event = json["event"] as? String else { return }
        let eventData = json["data"] as? [String: Any] ?? [:]
        guard let dot = event.lastIndex(of: ".") else { return }
        let rid = String(event[..<dot])
        let name = String(event[event.index(after: dot)...])

        switch name {
        case "change":
            let values = eventData["values"] as? [String: Any] ?? [:]
            lock.lock()
            var model = models[rid] ?? [:]
            for (key, value) in values {
                if let dict = value as? [String: Any], dict["action"] as? String == "delete" {
                    model.removeValue(forKey: key)
                } else {
                    model[key] = Self.unwrap(value)
                }
            }
            models[rid] = model
            let full = resolved(model)
            lock.unlock()
            onEvent(.modelChanged(rid: rid, model: full))
        case "add":
            ingest(eventData)
            if let ref = (eventData["value"] as? [String: Any])?["rid"] as? String {
                lock.lock()
                var refs = collections[rid] ?? []
                let idx = min(eventData["idx"] as? Int ?? refs.count, refs.count)
                refs.insert(ref, at: idx)
                collections[rid] = refs
                lock.unlock()
                onEvent(.collectionAdded(rid: rid, itemRid: ref))
            }
        case "remove":
            lock.lock()
            var refs = collections[rid] ?? []
            var removed: String?
            if let idx = eventData["idx"] as? Int, idx < refs.count {
                removed = refs.remove(at: idx)
            }
            collections[rid] = refs
            lock.unlock()
            if let removed { onEvent(.collectionRemoved(rid: rid, itemRid: removed)) }
        default:
            break
        }
    }

    /// Stores the `models` and `collections` sections of a response in the cache.
    private func ingest(_ result: [String: Any]) {
        lock.lock()
        if let newModels = result["models"] as? [String: [String: Any]] {
            for (rid, model) in newModels {
                models[rid] = model.mapValues(Self.unwrap)
            }
        }
        if let newCollections = result["collections"] as? [String: [Any]] {
            for (rid, items) in newCollections {
                collections[rid] = items.compactMap { ($0 as? [String: Any])?["rid"] as? String }
            }
        }
        lock.unlock()
    }

    /// RES wraps non-primitive values as `{"data": ...}`; unwrap those for easier consumption.
    private static func unwrap(_ value: Any) -> Any {
        if let dict = value as? [String: Any], dict.count == 1, let data = dict["data"] { return data }
        return value
    }
}
