import Foundation

/// UserDefaults-backed storage for non-secret state. The user itself is kept in the keychain.
final class LocalStore {
    static let shared = LocalStore()

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    enum Key: String, CaseIterable {
        case settings
        case pushToken = "push_token"
        case remoteNotificationToken = "remote_notification_token"
        case installationId = "installation_id"
        case middlewareRegistrationToken = "middleware_registration_token"
        case isLoggedInSomewhereElse = "is_logged_in_somewhere_else"
        case availableDestinations = "available_destinations"
        case selectedUserDestinationId = "selected_user_destination_id"
        case colleagues
        case sharedContacts
        case lastDialedNumber = "last_dialed_number"
        case currentColltactTab = "current_colltact_tab"
        case recentOutgoingNumbers = "recent_outgoing_numbers"
        case doNotShowOutgoingNumberSelector = "do_not_show_outgoing_number_selector"
        case previousSessionSettings = "previous_session_settings"
        case lastCallRatingAskedTime = "last_call_rating_asked_time"
        case appRatingSurveyActionCount = "app_rating_survey_action_count"
        case appRatingSurveyShownTime = "app_rating_survey_shown_time"
        case lastInstalledVersion = "last_installed_version"
    }

    func get<T: Decodable>(_ key: Key, as type: T.Type = T.self) -> T? {
        guard let data = defaults.data(forKey: key.rawValue) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    func set<T: Encodable>(_ value: T?, for key: Key) {
        guard let value, let data = try? encoder.encode(value) else {
            defaults.removeObject(forKey: key.rawValue)
            return
        }
        defaults.set(data, forKey: key.rawValue)
    }

    func string(_ key: Key) -> String? { defaults.string(forKey: key.rawValue) }
    func setString(_ value: String?, for key: Key) { defaults.set(value, forKey: key.rawValue) }
    func bool(_ key: Key) -> Bool { defaults.bool(forKey: key.rawValue) }
    func setBool(_ value: Bool, for key: Key) { defaults.set(value, forKey: key.rawValue) }

    func remove(_ key: Key) { defaults.removeObject(forKey: key.rawValue) }

    func clearAll(except preserved: [Key]) {
        for key in Key.allCases where !preserved.contains(key) {
            defaults.removeObject(forKey: key.rawValue)
        }
    }
}
