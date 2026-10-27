import Foundation
import Observation
import AVFoundation
import UserNotifications

/// The banner shown above the main tabs. One notice at a time, in the Flutter app's priority order.
enum Notice: Equatable {
    case microphoneDenied
    case notificationsDenied
    case noAppAccount(canChange: Bool)
    case temporaryRedirect(TemporaryRedirect, canChange: Bool)

    var title: String {
        switch self {
        case .microphoneDenied: return L10n.main.notice.microphone.title
        case .notificationsDenied: return L10n.main.notice.notifications.title
        case .noAppAccount: return L10n.main.notice.noAppAccount.title
        case .temporaryRedirect: return N("notice.temporaryRedirect.title")
        }
    }

    var message: String {
        switch self {
        case .microphoneDenied:
            return L10n.main.notice.microphone.content(appName: Brand.appName)
        case .notificationsDenied:
            return L10n.main.notice.notifications.content
        case .noAppAccount(let canChange):
            return canChange
                ? L10n.main.notice.noAppAccount.content(appName: Brand.appName)
                : L10n.main.notice.noAppAccount.noPermission.content
        case .temporaryRedirect(let redirect, _):
            return N("notice.temporaryRedirect.content", [
                "destination": redirect.destinationName,
                "date": redirect.endsAt.formatted(date: .abbreviated, time: .shortened),
            ])
        }
    }

    var actionTitle: String? {
        switch self {
        case .microphoneDenied, .notificationsDenied: return L10n.main.notice.actions.givePermission
        case .noAppAccount(let canChange): return canChange ? L10n.main.notice.actions.selectAccount : nil
        case .temporaryRedirect(_, let canChange): return canChange ? L10n.main.temporaryRedirect.actions.changeRedirect.label : nil
        }
    }
}

@MainActor
@Observable
final class NoticeManager {
    private(set) var notice: Notice?
    private var dismissed = false
    private weak var session: SessionManager?

    func bind(session: SessionManager) { self.session = session }

    func dismiss() {
        dismissed = true
        notice = nil
    }

    func check() async {
        guard !dismissed, let user = session?.user else {
            notice = nil
            return
        }
        let microphoneDenied = AVAudioApplication.shared.recordPermission == .denied
        let notificationsDenied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied

        if microphoneDenied {
            notice = .microphoneDenied
        } else if notificationsDenied {
            notice = .notificationsDenied
        } else if !user.isAllowedVoipCalling {
            notice = .noAppAccount(canChange: user.hasPermission(.canChangeAppAccount))
        } else if let redirect = user.client.currentTemporaryRedirect {
            notice = .temporaryRedirect(redirect, canChange: user.hasPermission(.canChangeTemporaryRedirect))
        } else {
            notice = nil
        }
    }
}
