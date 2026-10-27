import Foundation
import Observation

/// Live colleague presence and the logged-in user's availability over Resgate.
@MainActor
@Observable
final class PresenceManager {
    private(set) var isConnected = false
    /// Presence keyed by colleague user uuid.
    private(set) var presence: [String: ColleaguePresence] = [:]
    /// Called when a payload arrives for a colleague we don't know yet.
    var onUnknownColleague: () -> Void = {}

    struct ColleaguePresence: Equatable {
        var status: ColleagueAvailabilityStatus
        var context: [ColleagueContext]
        var destination: ColleagueDestination?
        var internalNumber: String
    }

    private var client: ResClient?
    private weak var session: SessionManager?
    private var reconnectAttempts = 0
    private var reconnectTask: Task<Void, Never>?
    private var shouldBeConnected = false

    func bind(session: SessionManager) { self.session = session }

    func connect() {
        guard let session, let user = session.user, session.isOnboarded else { return }
        shouldBeConnected = true
        guard client == nil else { return }
        let client = ResClient(url: Brand.resgateURL)
        self.client = client
        client.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event, user: user) }
        }
        AppLog.info("Connecting to Resgate")
        client.connect()
        Task { await authenticateAndSubscribe(client: client, user: user) }
    }

    func disconnect() {
        shouldBeConnected = false
        reconnectTask?.cancel()
        client?.disconnect()
        client = nil
        isConnected = false
    }

    func refresh() {
        disconnect()
        connect()
    }

    private func authenticateAndSubscribe(client: ResClient, user: User) async {
        do {
            try await client.handshake()
            try await client.auth(token: user.token)
            let clientRid = "availability.client.\(user.client.uuid)"
            let deviceRid = "\(clientRid).user.\(user.uuid).device"
            try await client.subscribe(clientRid)
            try await client.subscribe(deviceRid)
            isConnected = true
            reconnectAttempts = 0
            for item in client.items(for: clientRid) { handleAvailability(rid: item.rid, model: item.model, user: user) }
            for item in client.items(for: deviceRid) { handleDevice(model: item.model) }
            AppLog.info("Resgate connected and subscribed")
        } catch {
            AppLog.warning("Resgate setup failed: \(error)")
            client.disconnect()
            self.client = nil
            isConnected = false
            scheduleReconnect()
        }
    }

    private func handle(_ event: ResClient.Event, user: User) {
        switch event {
        case .connected:
            break
        case .disconnected(let error):
            AppLog.warning("Resgate disconnected: \(String(describing: error))")
            client = nil
            isConnected = false
            scheduleReconnect()
        case .modelChanged(let rid, let model):
            if rid.hasSuffix(".device") || rid.range(of: "\\.device\\.[0-9]+$", options: .regularExpression) != nil {
                handleDevice(model: model)
            } else if model["user_uuid"] == nil, let parent = client?.parent(of: rid),
                      let parentModel = client?.items(for: parent).first?.model {
                // A nested resource (e.g. the selected destination) changed; re-read its owner.
                handleAvailability(rid: parent, model: parentModel, user: user)
            } else {
                handleAvailability(rid: rid, model: model, user: user)
            }
        case .collectionAdded(_, let itemRid):
            if let model = client?.items(for: itemRid).first?.model {
                handleAvailability(rid: itemRid, model: model, user: user)
            }
        case .collectionRemoved:
            break
        }
    }

    private func scheduleReconnect() {
        guard shouldBeConnected, reconnectTask == nil else { return }
        let delay = min(pow(2.0, Double(reconnectAttempts)), 60)
        reconnectAttempts += 1
        AppLog.info("Resgate reconnect in \(delay)s")
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.reconnectTask = nil
            if self.shouldBeConnected { self.connect() }
        }
    }

    // MARK: Payload handling

    private func handleAvailability(rid: String, model: [String: Any], user: User) {
        guard rid.contains(".user."), !rid.hasSuffix(".device"), rid.range(of: "\\.device\\.", options: .regularExpression) == nil else { return }
        guard let userUuid = model["user_uuid"] as? String else { return }

        let availability = ColleagueAvailabilityStatus(serverValue: model["availability"] as? String)
        let userStatus = ColleagueAvailabilityStatus(serverValue: model["user_status"] as? String)
        let context = (model["context"] as? [String] ?? []).compactMap(ColleagueContext.init(serverValue:))
        let destinationJson = model["destination"] as? [String: Any]
        let destinationType = ColleagueDestinationType(serverValue: destinationJson?["type"] as? String)
        let portalId = destinationJson?["portal_id"] as? Int
        let internalNumber = (model["internal_number"] as? Int).map(String.init) ?? (model["internal_number"] as? String) ?? ""

        if userUuid == user.uuid {
            if portalId == nil, let raw = model["destination"], !(raw is NSNull) {
                AppLog.warning("Unrecognised destination payload: \(raw)")
            }
            session?.applyRemoteSelectedDestination(id: portalId)
            session?.isRingingDeviceOffline = userStatus != .offline && destinationType == .voipAccount && availability == .offline
            if let status = UserAvailabilityStatus(colleagueStatus: userStatus) {
                session?.settings.availabilityStatus = status
            }
            return
        }

        presence[userUuid] = ColleaguePresence(
            status: availability,
            context: context,
            destination: ColleagueDestination(number: internalNumber, type: destinationType),
            internalNumber: internalNumber
        )
    }

    private func handleDevice(model: [String: Any]) {
        guard let accountId = model["account_id"] as? Int, let isOnline = model["is_online"] as? Bool else { return }
        session?.updateDestinationIsOnline(accountId: accountId, isOnline: isOnline)
    }
}

private extension UserAvailabilityStatus {
    init?(colleagueStatus: ColleagueAvailabilityStatus) {
        switch colleagueStatus {
        case .available, .busy: self = .available
        case .availableForColleagues: self = .availableForColleagues
        case .doNotDisturb: self = .doNotDisturb
        case .offline: self = .offline
        case .unknown: return nil
        }
    }
}
