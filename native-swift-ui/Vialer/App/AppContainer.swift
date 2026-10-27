import Foundation
import Observation
import UIKit

enum MainTab: Int { case dialer, contacts, recents, settings }

/// Composition root: wires the managers together and reacts to app-wide events.
@MainActor
@Observable
final class AppContainer {
    let session = SessionManager()
    let calls = CallManager()
    let presence = PresenceManager()
    let colltacts = ColltactsStore()
    let recents = RecentsStore()
    let outgoingCalls: OutgoingCallCoordinator
    let notices = NoticeManager()
    let feedback = FeedbackManager()
    let connectivity = ConnectivityMonitor()
    let updates = UpdateChecker()

    var selectedTab: MainTab = .contacts
    /// Number to pre-fill in the dialer, e.g. from a Siri intent or the vialercall:// URL scheme.
    var pendingDialerNumber: String?
    var showOnboarding: Bool

    /// Debug-only: `--ui-preview` launches straight into the main screen with a fake user and sample
    /// data, and `--tab=<dialer|contacts|recents|settings>` picks the initial tab. No network calls.
    static let isUIPreview: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--ui-preview")
        #else
        return false
        #endif
    }()

    init() {
        ErrorTracking.start()
        RemoteLogging.shared.userIdentifier = session.user?.uuid
        RemoteLogging.shared.isEnabled = session.settings.remoteLogging
        if let user = session.user {
            ErrorTracking.setUser(id: user.uuid)
            Metrics.identify(user.uuid, traits: ["brand": Brand.identifier])
        }
        if Self.isUIPreview {
            session.installPreviewUser()
            recents.installPreviewData()
            colltacts.installPreviewData()
            if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--tab=") }) {
                switch arg.dropFirst("--tab=".count) {
                case "dialer": selectedTab = .dialer
                case "recents": selectedTab = .recents
                case "settings": selectedTab = .settings
                case "call": calls.installPreviewCall()
                case "survey": feedback.surveyToShow = .messagingApps(username: "Alex")
                case "rating": feedback.surveyToShow = .appRating
                default: selectedTab = .contacts
                }
            }
        }
        showOnboarding = !session.isOnboarded
        outgoingCalls = OutgoingCallCoordinator(session: session, calls: calls)
        presence.bind(session: session)
        session.presenceIsConnected = { [weak self] in self?.presence.isConnected ?? false }
        notices.bind(session: session)
        feedback.bind(session: session)
        calls.onCallEnded = { [weak self] call, routes in self?.feedback.callEnded(call, usedRoutes: routes) }
        connectivity.onReconnected = { [weak self] in
            guard let self, session.isOnboarded else { return }
            presence.connect()
            Task { await self.session.refreshUser() }
        }
        colltacts.bind(session: session, presence: presence)
        recents.bind(session: session)

        calls.middleware.currentUser = session.user
        calls.middleware.isVoipEnabled = session.settings.useVoip
        calls.middleware.onLoggedInSomewhereElse = { [weak self] in self?.session.logout() }

        session.onLoggedOut = { [weak self] in
            guard let self else { return }
            calls.middleware.currentUser = nil
            presence.disconnect()
            Task { await self.calls.stop() }
            showOnboarding = true
            selectedTab = .contacts
        }
        session.onUserRefreshed = { [weak self] user in
            guard let self else { return }
            calls.middleware.currentUser = user
            calls.middleware.isVoipEnabled = session.settings.useVoip
            guard session.isOnboarded else { return }
            calls.start(user: user, settings: session.settings)
            calls.middleware.register()
            presence.connect()
        }

        if session.isOnboarded, let user = session.user, !Self.isUIPreview {
            calls.start(user: user, settings: session.settings)
        }
    }

    func onAppear() {
        guard session.isOnboarded, !Self.isUIPreview else { return }
        feedback.checkSurveys(isInCall: calls.isInCall)
        updates.check()
        Task { await session.refreshUser() }
        Task { await session.fetchAvailabilityStatus() }
        Task { await colltacts.loadContacts() }
        Task { await colltacts.loadSharedContacts() }
        Task { await colltacts.loadColleagues() }
        presence.connect()
    }

    func onForeground() {
        guard session.isOnboarded, !Self.isUIPreview else { return }
        calls.reconcileOnForeground()
        Task { await session.refreshUser() }
        Task { await notices.check() }
        presence.connect()
    }

    func onBackground() {
        presence.disconnect()
    }

    func onboardingCompleted() {
        session.completeOnboarding()
        showOnboarding = false
        onAppear()
    }

    func logout() {
        calls.middleware.unregister()
        session.logout()
    }

    /// Entry point for calls from anywhere in the app.
    func call(_ number: String) {
        outgoingCalls.call(number)
    }

    func openDialer(with number: String) {
        pendingDialerNumber = number
        selectedTab = .dialer
    }

    func handleMissedCallNotificationTap() {
        selectedTab = .recents
    }

    func handle(url: URL) {
        guard url.scheme == "vialercall", url.host == "call",
              let number = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "number" })?.value else { return }
        Metrics.track("call-from-os-initiated")
        call(number.replacingOccurrences(of: "[^0-9\\+]", with: "", options: .regularExpression))
    }
}
