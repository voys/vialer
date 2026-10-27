import SwiftUI
import Intents
import UserNotifications

@main
struct VialerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
                .tint(Theme.primary)
                .onAppear {
                    appDelegate.container = container
                    container.onAppear()
                }
                .onOpenURL { container.handle(url: $0) }
                .onContinueUserActivity("INStartCallIntent") { handleCallIntent($0) }
                .onContinueUserActivity("INStartAudioCallIntent") { handleCallIntent($0) }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active: container.onForeground()
                    case .background: container.onBackground()
                    default: break
                    }
                }
        }
    }

    private func handleCallIntent(_ activity: NSUserActivity) {
        let handle: String?
        if let intent = activity.interaction?.intent as? INStartCallIntent {
            handle = intent.contacts?.first?.personHandle?.value
        } else if let intent = activity.interaction?.intent as? INStartAudioCallIntent {
            handle = intent.contacts?.first?.personHandle?.value
        } else {
            handle = nil
        }
        guard let handle else { return }
        container.openDialer(with: handle.replacingOccurrences(of: "[^0-9\\+]", with: "", options: .regularExpression))
    }
}

struct RootView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        @Bindable var calls = container.calls
        @Bindable var outgoingCalls = container.outgoingCalls
        @Bindable var feedback = container.feedback
        Group {
            if container.showOnboarding {
                OnboardingFlow()
            } else {
                MainTabView()
            }
        }
        .sheet(item: $outgoingCalls.pendingPrompt) { pending in
            OutgoingNumberPromptView(pending: pending)
        }
        .sheet(item: $feedback.callToRate) { CallFeedbackView(rated: $0) }
        .sheet(item: $feedback.surveyToShow) { SurveyView(survey: $0) }
        .fullScreenCover(isPresented: $calls.isCallScreenPresented) {
            CallView()
        }
        .alert(item: $calls.failure) { failure in
            Alert(title: Text(L10n.main.call.error.title), message: Text(failure.message), dismissButton: .default(Text(L10n.generic.button.ok)))
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var container: AppContainer?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        LocalStore.shared.setString(deviceToken.map { String(format: "%02hhx", $0) }.joined(), for: .remoteNotificationToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        AppLog.warning("Failed to register for remote notifications: \(error)")
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if response.notification.request.identifier == NotificationRequestIdentifiers.missedCalls.rawValue {
            await MainActor.run { container?.handleMissedCallNotificationTap() }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}
