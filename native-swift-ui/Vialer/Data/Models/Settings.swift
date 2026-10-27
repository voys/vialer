import Foundation

/// All user settings, persisted as one JSON blob. Mirrors the Flutter AppSetting/CallSetting enums.
struct Settings: Codable, Equatable {
    var hasCompletedOnboarding = false

    // AppSetting
    var remoteLogging = false
    var showCallsInNativeRecents = true
    var showTroubleshooting = false
    var showClientCalls = false
    var showOnlineColleaguesOnly = true
    var alwaysShowCallerNameInRecents = false
    var showSurveys = true

    // CallSetting
    var useVoip = true
    var outgoingNumber: OutgoingNumber = .number("", description: nil)
    var mobileNumber = ""
    var usePhoneRingtone = false
    var destinationId: Int = 0
    var useMobileNumberAsFallback = false
    var availabilityStatus: UserAvailabilityStatus = .available

    /// Settings that survive a logout, as in the Flutter app.
    func crossSessionValues() -> Settings {
        var s = Settings()
        s.usePhoneRingtone = usePhoneRingtone
        s.remoteLogging = remoteLogging
        s.showCallsInNativeRecents = showCallsInNativeRecents
        s.showClientCalls = showClientCalls
        s.alwaysShowCallerNameInRecents = alwaysShowCallerNameInRecents
        s.showOnlineColleaguesOnly = showOnlineColleaguesOnly
        s.showTroubleshooting = showTroubleshooting
        return s
    }
}
