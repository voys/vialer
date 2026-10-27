import Foundation
import Observation

enum LoginOutcome {
    case success
    case twoFactorRequired
    case passwordChangeRequired
    case invalidCredentials
    case noConnection
    case failed(String)
}

/// Owns the logged-in user, settings, destinations and availability. Replaces the Flutter
/// AuthRepository, RefreshUser, SettingsRepository and DestinationRepository.
@MainActor
@Observable
final class SessionManager {
    private(set) var user: User?
    var settings: Settings {
        didSet { store.set(settings, for: .settings) }
    }
    private(set) var availableDestinations: [Destination]
    private(set) var selectedUserDestinationId: Int?
    private(set) var isRefreshing = false
    /// Set when the user's chosen status is not offline but the selected VoIP device is.
    var isRingingDeviceOffline = false
    /// Whether the Resgate connection is up; set by the container.
    var presenceIsConnected: (() -> Bool)?
    private(set) var hasUnreadFeatureAnnouncements = false
    /// Set for a minute after the API rate-limits a request.
    private(set) var rateLimitedUntil: Date?
    var isRateLimited: Bool { rateLimitedUntil.map { $0 > Date() } ?? false }

    /// Fired after logout so the UI can return to onboarding.
    var onLoggedOut: () -> Void = {}
    /// Fired after a successful login or refresh, for VoIP start and middleware registration.
    var onUserRefreshed: (User) -> Void = { _ in }

    private let api = VoipgridAPI()
    private let statusAPI = UserStatusAPI()
    private let store = LocalStore.shared
    private static let userKey = "session_user"
    private var lastRefresh: Date?

    init() {
        settings = store.get(.settings) ?? Settings()
        availableDestinations = store.get(.availableDestinations) ?? []
        selectedUserDestinationId = store.get(.selectedUserDestinationId)
        if let data = Keychain.get(Self.userKey), let stored = try? JSONDecoder().decode(User.self, from: data) {
            user = stored
            HTTPClient.shared.credentials = stored.credentials
        }
        HTTPClient.shared.onUnauthorized = { [weak self] url in
            Task { @MainActor in self?.handleUnauthorized(url: url) }
        }
        HTTPClient.shared.onRateLimited = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let until = Date().addingTimeInterval(60)
                self.rateLimitedUntil = until
                try? await Task.sleep(for: .seconds(60))
                if self.rateLimitedUntil == until { self.rateLimitedUntil = nil }
            }
        }
    }

    var isAuthenticated: Bool { user != nil }
    var isOnboarded: Bool { isAuthenticated && settings.hasCompletedOnboarding }
    var canUseVoip: Bool { settings.useVoip && (user?.isAllowedVoipCalling ?? false) }

    var selectedDestination: Destination {
        switch settings.destinationId {
        case -1: return .notAvailable
        case 0: return .unknown
        default: return availableDestinations.find(id: settings.destinationId) ?? .unknown
        }
    }

    /// Debug-only: a fake logged-in user so screens can be previewed on the simulator without
    /// credentials. Nothing is persisted to the keychain.
    func installPreviewUser() {
        user = User(
            uuid: "preview-user", email: "jane@example.com", firstName: "Jane", preposition: "", lastName: "Doe",
            token: "preview-token", appAccountUrl: "https://partner.voys.co/api/phoneaccount/basic/phoneaccount/123/",
            webphoneAccountId: nil, internalNumber: "201",
            client: Client(
                id: 1, uuid: "preview-client", name: "Example B.V.", url: "", voip: .fallback,
                outgoingNumbers: [.number("+31501234567", description: "Main"), .number("+31507654321", description: "Sales")]
            ),
            appAccount: nil,
            permissions: Set(Permission.allCases)
        )
        availableDestinations = [
            .phoneAccount(id: 123, description: "App account", accountId: 123, internalNumber: 201, isOnline: true),
            .phoneAccount(id: 124, description: "Desk phone", accountId: 124, internalNumber: 202, isOnline: true),
        ]
        settings.hasCompletedOnboarding = true
        settings.destinationId = 123
        settings.showClientCalls = true
    }

    // MARK: Login / logout

    func login(email: String, password: String, twoFactorCode: String? = nil) async -> LoginOutcome {
        do {
            let token = try await api.requestToken(email: email, password: password, twoFactorCode: twoFactorCode)
            let systemUser = try await api.getSystemUser(email: email, token: token)
            var newUser = User(
                uuid: systemUser.uuid,
                email: systemUser.email,
                firstName: systemUser.firstName,
                preposition: systemUser.preposition,
                lastName: systemUser.lastName,
                token: token,
                appAccountUrl: systemUser.appAccountUrl,
                client: Client(
                    id: systemUser.clientId,
                    uuid: systemUser.clientUuid,
                    name: systemUser.clientName,
                    url: systemUser.clientUrl,
                    voip: .fallback
                )
            )
            restoreCrossSessionSettings()
            settings.mobileNumber = systemUser.mobileNumber ?? ""
            settings.outgoingNumber = OutgoingNumber(serverValue: systemUser.outgoingCli ?? "")
            newUser = await refreshTasks(for: newUser)
            persist(newUser)
            Metrics.track("user-logged-in", ["two-factor": twoFactorCode != nil])
            Metrics.identify(newUser.uuid, traits: ["brand": Brand.identifier])
            ErrorTracking.setUser(id: newUser.uuid)
            RemoteLogging.shared.userIdentifier = newUser.uuid
            onUserRefreshed(newUser)
            return .success
        } catch LoginError.twoFactorRequired {
            return .twoFactorRequired
        } catch LoginError.needToChangePassword {
            return .passwordChangeRequired
        } catch LoginError.invalidCredentials {
            return .invalidCredentials
        } catch LoginError.noConnection {
            return .noConnection
        } catch HTTPError.noConnection {
            return .noConnection
        } catch {
            ErrorTracking.capture(error, context: "login")
            return .failed(error.localizedDescription)
        }
    }

    func changePassword(email: String, currentPassword: String, newPassword: String) async -> Bool {
        await api.changePassword(email: email, currentPassword: currentPassword, newPassword: newPassword)
    }

    func requestPasswordReset(email: String) async -> Bool {
        await api.requestPasswordReset(email: email)
    }

    func completeOnboarding() {
        settings.hasCompletedOnboarding = true
        if let user { onUserRefreshed(user) }
    }

    func logout() {
        AppLog.info("Logging out")
        let preserved = settings.crossSessionValues()
        store.set(preserved, for: .previousSessionSettings)
        Keychain.delete(Self.userKey)
        user = nil
        ErrorTracking.setUser(id: nil)
        RemoteLogging.shared.userIdentifier = nil
        RemoteLogging.shared.isEnabled = false
        HTTPClient.shared.credentials = nil
        store.clearAll(except: [.pushToken, .remoteNotificationToken, .previousSessionSettings, .installationId])
        settings = Settings()
        availableDestinations = []
        selectedUserDestinationId = nil
        onLoggedOut()
    }

    private func handleUnauthorized(url: URL) {
        let path = url.path
        if path.contains("permission/systemuser/profile") || path.contains("permission/apitoken") {
            AppLog.warning("Unauthorized response from \(path), logging out")
            if isAuthenticated { logout() }
        }
    }

    private func restoreCrossSessionSettings() {
        if let previous: Settings = store.get(.previousSessionSettings) {
            var s = previous.crossSessionValues()
            s.hasCompletedOnboarding = settings.hasCompletedOnboarding
            settings = s
            store.remove(.previousSessionSettings)
        }
    }

    // MARK: Refresh

    /// Re-fetches everything about the user. At most once per minute unless forced.
    func refreshUser(force: Bool = false) async {
        guard let current = user, !isRefreshing else { return }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 60 { return }
        isRefreshing = true
        defer { isRefreshing = false }
        if store.bool(.isLoggedInSomewhereElse) {
            AppLog.warning("Logged in somewhere else, logging out")
            logout()
            return
        }
        do {
            let systemUser = try await api.getSystemUser()
            var refreshed = current
            refreshed.firstName = systemUser.firstName
            refreshed.preposition = systemUser.preposition
            refreshed.lastName = systemUser.lastName
            refreshed.appAccountUrl = systemUser.appAccountUrl
            refreshed.client.name = systemUser.clientName
            settings.mobileNumber = systemUser.mobileNumber ?? ""
            settings.outgoingNumber = OutgoingNumber(serverValue: systemUser.outgoingCli ?? "")
            refreshed = await refreshTasks(for: refreshed)
            persist(refreshed)
            lastRefresh = Date()
            onUserRefreshed(refreshed)
        } catch LoginError.needToChangePassword {
            AppLog.warning("User needs to change password; logging out")
            logout()
        } catch {
            AppLog.warning("User refresh failed: \(error)")
        }
    }

    private func refreshTasks(for input: User) async -> User {
        var user = input
        // Permissions gate some of the other tasks, so they run first.
        if let permissions = try? await api.getPermissions() {
            user.permissions = permissions
        }
        // The remaining tasks are independent; run them concurrently.
        let clientUuid = user.client.uuid
        let clientId = user.client.id
        let canViewVoicemails = user.hasPermission(.canViewVoicemailAccounts)
        let canChangeRedirect = user.hasPermission(.canChangeTemporaryRedirect)
        let canChangeOpeningHours = user.hasPermission(.canChangeOpeningHours)
        async let appAccount = try? api.getAppAccount()
        async let voipConfig = try? api.getClientVoipConfig()
        async let details = try? api.getUserDetails()
        async let outgoingNumbers = try? api.getOutgoingNumbers(clientUuid: clientUuid)
        async let voicemails: [VoicemailAccount]? = canViewVoicemails ? (try? api.getVoicemailAccounts(clientId: clientId)) : nil
        async let openingHoursModuleId: String? = canChangeOpeningHours ? await api.getOpeningHoursModuleId(clientUuid: clientUuid) : nil
        async let unreadAnnouncements = FeatureAnnouncementsAPI().hasUnreadAnnouncements()

        if let voicemails = await voicemails { user.client.voicemailAccounts = voicemails }
        if canChangeRedirect {
            user.client.currentTemporaryRedirect = try? await BusinessAvailabilityAPI()
                .currentRedirect(clientUuid: clientUuid, voicemails: user.client.voicemailAccounts)
        }
        user.client.openingHoursModuleId = await openingHoursModuleId
        hasUnreadFeatureAnnouncements = await unreadAnnouncements

        if let fetchedAccount = await appAccount {
            if !(fetchedAccount.useOpus && fetchedAccount.useEncryption) {
                await api.forceOpusAndEncryption()
                var forced = fetchedAccount
                forced.useOpus = true
                forced.useEncryption = true
                user.appAccount = forced
            } else {
                user.appAccount = fetchedAccount
            }
        }
        if let voipConfig = await voipConfig { user.client.voip = voipConfig }
        if let numbers = await outgoingNumbers { user.client.outgoingNumbers = numbers }
        if let details = await details {
            user.internalNumber = details.internalNumber
            user.webphoneAccountId = details.webphoneAccountId
            user.client.enabledModules = details.enabledModules
            updateDestinations(details.availableDestinations)
            if let id = details.selectedDestinationId {
                selectedUserDestinationId = id
                store.set(id, for: .selectedUserDestinationId)
            }
            settings.destinationId = details.selectedDestination?.identifier ?? Destination.notAvailable.identifier
            settings.useMobileNumberAsFallback = details.useMobileNumberAsFallback
        }
        return user
    }

    private func persist(_ newUser: User) {
        user = newUser
        HTTPClient.shared.credentials = newUser.credentials
        if let data = try? JSONEncoder().encode(newUser) {
            Keychain.set(data, for: Self.userKey)
        }
    }

    // MARK: Destinations

    private func updateDestinations(_ destinations: [Destination]) {
        let stale = availableDestinations
        availableDestinations = destinations.map { destination in
            if let accountId = destination.accountId,
               let old = stale.first(where: { $0.accountId == accountId }) {
                return destination.settingOnline(old.isOnline)
            }
            return destination
        }
        store.set(availableDestinations, for: .availableDestinations)
    }

    func updateDestinationIsOnline(accountId: Int, isOnline: Bool) {
        availableDestinations = availableDestinations.map {
            $0.accountId == accountId ? $0.settingOnline(isOnline) : $0
        }
        store.set(availableDestinations, for: .availableDestinations)
    }

    /// Applies a destination pushed from Resgate; refreshes from the API if it's unknown.
    func applyRemoteSelectedDestination(id: Int?) {
        guard let id else {
            AppLog.info("Remote selected destination: none")
            settings.destinationId = Destination.notAvailable.identifier
            return
        }
        if let found = availableDestinations.find(id: id) {
            AppLog.info("Remote selected destination: \(id)")
            settings.destinationId = found.identifier
        } else {
            AppLog.info("Remote selected destination \(id) unknown locally; refreshing user")
            Task { await refreshUser(force: true) }
        }
    }

    func changeDestination(_ destination: Destination) async -> Bool {
        if selectedUserDestinationId == nil {
            AppLog.warning("No selected user destination id yet; refreshing user details first")
            await refreshUser(force: true)
        }
        guard let selectedUserDestinationId else {
            AppLog.warning("Cannot change destination: still no selected user destination id")
            return false
        }
        AppLog.info("Changing destination to \(destination.identifier) via selected user destination \(selectedUserDestinationId)")
        let previous = settings.destinationId
        settings.destinationId = destination.identifier
        let ok = await api.setDestination(selectedUserDestinationId: selectedUserDestinationId, destination: destination)
        if !ok { settings.destinationId = previous }
        Metrics.track("destination-changed", ["success": ok])
        // Without the websocket nothing pushes the new state back, so pull it like the Flutter app.
        if ok, presenceIsConnected?() != true { await refreshUser(force: true) }
        return ok
    }

    // MARK: Availability status

    func fetchAvailabilityStatus() async {
        guard let user else { return }
        if let status = try? await statusAPI.getStatus(user: user) {
            settings.availabilityStatus = status
        }
    }

    func changeAvailabilityStatus(_ status: UserAvailabilityStatus) async -> Bool {
        guard let user else { return false }
        let previous = settings.availabilityStatus
        settings.availabilityStatus = status
        let ok = await statusAPI.setStatus(user: user, status: status)
        if !ok { settings.availabilityStatus = previous }
        return ok
    }

    // MARK: Other settings

    func changeMobileNumber(_ number: String) async -> Bool {
        let ok = await api.changeMobileNumber(number)
        if ok { settings.mobileNumber = number }
        return ok
    }

    func changeOutgoingNumber(_ number: OutgoingNumber) async -> Bool {
        guard let user else { return false }
        let value = number.isSuppressed ? OutgoingNumber.suppressedValue : number.value
        let ok = await api.changeOutgoingNumber(user: user, number: value)
        if ok {
            settings.outgoingNumber = number
            if !number.isSuppressed {
                var recents: [OutgoingNumber] = store.get(.recentOutgoingNumbers) ?? []
                recents.removeAll { $0 == number }
                recents.insert(number, at: 0)
                store.set(Array(recents.prefix(5)), for: .recentOutgoingNumbers)
            }
        }
        return ok
    }

    var recentOutgoingNumbers: [OutgoingNumber] { store.get(.recentOutgoingNumbers) ?? [] }

    func setUseMobileNumberAsFallback(_ enabled: Bool) async -> Bool {
        guard let user else { return false }
        let ok = await api.setUseMobileNumberAsFallback(user: user, enabled: enabled)
        if ok { settings.useMobileNumberAsFallback = enabled }
        return ok
    }

    // MARK: Temporary redirect

    func setTemporaryRedirect(_ redirect: TemporaryRedirect) async -> Bool {
        guard var user else { return false }
        let api = BusinessAvailabilityAPI()
        let ok = redirect.id == nil
            ? await api.create(clientUuid: user.client.uuid, redirect: redirect)
            : await api.update(clientUuid: user.client.uuid, redirect: redirect)
        guard ok else { return false }
        user.client.currentTemporaryRedirect = try? await api.currentRedirect(clientUuid: user.client.uuid, voicemails: user.client.voicemailAccounts)
        persist(user)
        Metrics.track("temporary-redirect-changed")
        return true
    }

    func cancelTemporaryRedirect() async -> Bool {
        guard var user, let id = user.client.currentTemporaryRedirect?.id else { return false }
        let ok = await BusinessAvailabilityAPI().delete(clientUuid: user.client.uuid, id: id)
        guard ok else { return false }
        user.client.currentTemporaryRedirect = nil
        persist(user)
        Metrics.track("temporary-redirect-cancelled")
        return true
    }

    func refreshVoicemailAccounts() async {
        guard var user, user.hasPermission(.canViewVoicemailAccounts),
              let voicemails = try? await api.getVoicemailAccounts(clientId: user.client.id) else { return }
        user.client.voicemailAccounts = voicemails
        persist(user)
    }

    func markFeatureAnnouncementsRead() { hasUnreadFeatureAnnouncements = false }

    func portalAutoLoginURL(next: String) async -> URL? {
        guard let user, let token = try? await api.getAutoLoginToken() else { return nil }
        var components = URLComponents(url: Brand.portalURL.appendingPathComponent("user/autologin/"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "username", value: user.email),
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "next", value: next),
        ]
        return components?.url
    }
}
