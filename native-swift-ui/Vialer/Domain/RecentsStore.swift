import Foundation
import Observation

enum RecentsScope: String, CaseIterable, Identifiable {
    case personal, client
    var id: String { rawValue }

    var title: String {
        switch self {
        case .personal: return L10n.main.recent.tabs.personal
        case .client: return L10n.main.recent.tabs.all
        }
    }
}

/// Paged recent calls, personal and client-wide.
@MainActor
@Observable
final class RecentsStore {
    private(set) var records: [RecentsScope: [CallRecord]] = [.personal: [], .client: []]
    private(set) var isLoading = false
    private(set) var hasMore: [RecentsScope: Bool] = [.personal: true, .client: true]
    private(set) var loadedPages: [RecentsScope: Int] = [.personal: 0, .client: 0]
    var onlyMissed = false {
        didSet { if oldValue != onlyMissed { Task { await reloadAll() } } }
    }

    private let api = VoipgridAPI()
    private weak var session: SessionManager?

    func bind(session: SessionManager) { self.session = session }

    /// Debug-only sample data for simulator previews.
    func installPreviewData() {
        let now = Date()
        func record(_ id: String, name: String?, number: String, inbound: Bool, answered: Bool, minutesAgo: Double, internalCall: Bool = false) -> CallRecord {
            CallRecord(
                id: id, callType: internalCall ? .colleague : .outside, callDirection: inbound ? .inbound : .outbound,
                answered: answered, answeredElsewhere: false, duration: answered ? 125 : 0,
                date: now.addingTimeInterval(-minutesAgo * 60),
                caller: CallParty(number: inbound ? number : "201", type: inbound ? .other : .app, name: inbound ? name : "Jane Doe"),
                destination: CallParty(number: inbound ? "201" : number, type: inbound ? .app : .other, name: inbound ? "Jane Doe" : name),
                summary: nil
            )
        }
        records[.personal] = [
            record("1", name: "Alex Bakker", number: "+31612345678", inbound: true, answered: true, minutesAgo: 12),
            record("2", name: nil, number: "+31201234567", inbound: true, answered: false, minutesAgo: 95),
            record("3", name: "Sam de Vries", number: "203", inbound: false, answered: true, minutesAgo: 240, internalCall: true),
            record("4", name: "Chris Jansen", number: "+31687654321", inbound: false, answered: true, minutesAgo: 1500),
            record("5", name: nil, number: "+31301112222", inbound: true, answered: false, minutesAgo: 2900),
        ]
        loadedPages[.personal] = 1
        hasMore[.personal] = false
    }

    func reloadAll() async {
        for scope in RecentsScope.allCases {
            records[scope] = []
            loadedPages[scope] = 0
            hasMore[scope] = true
        }
        await refresh(scope: .personal)
    }

    /// Reloads the first page and replaces the list only once it has arrived, so the list stays
    /// on screen (and the pull-to-refresh task alive) during the request.
    func refresh(scope: RecentsScope) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await fetch(scope: scope, page: 1)
            records[scope] = fetched
            loadedPages[scope] = 1
            hasMore[scope] = !fetched.isEmpty
        } catch {
            if !Self.isCancellation(error) { AppLog.warning("Failed to refresh recent calls (\(scope)): \(error)") }
        }
    }

    func loadMore(scope: RecentsScope) async {
        guard !isLoading, hasMore[scope] == true else { return }
        isLoading = true
        defer { isLoading = false }
        let page = (loadedPages[scope] ?? 0) + 1
        do {
            let fetched = try await fetch(scope: scope, page: page)
            loadedPages[scope] = page
            if fetched.isEmpty { hasMore[scope] = false }
            let existing = Set(records[scope]?.map(\.id) ?? [])
            records[scope, default: []] += fetched.filter { !existing.contains($0.id) }
        } catch {
            if Self.isCancellation(error) { return }
            AppLog.warning("Failed to load recent calls (\(scope)): \(error)")
            if page == 1 { hasMore[scope] = false }
        }
    }

    private func fetch(scope: RecentsScope, page: Int) async throws -> [CallRecord] {
        var fetched: [CallRecord]
        switch scope {
        case .personal:
            fetched = try await api.getPersonalCalls(page: page, onlyMissed: onlyMissed)
        case .client:
            fetched = try await api.getClientCalls(page: page, onlyMissed: onlyMissed, userPhoneAccountIds: userPhoneAccountIds)
        }
        if onlyMissed { fetched = fetched.filter(\.isInbound) }
        return fetched
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if case HTTPError.transport(let inner) = error, (inner as? URLError)?.code == .cancelled { return true }
        return false
    }

    private var userPhoneAccountIds: [Int] {
        guard let session else { return [] }
        return session.availableDestinations.phoneAccounts.compactMap { $0.accountId }
            + [session.user?.appAccountId, session.user?.webphoneAccountId].compactMap { $0.flatMap(Int.init) }
    }
}
