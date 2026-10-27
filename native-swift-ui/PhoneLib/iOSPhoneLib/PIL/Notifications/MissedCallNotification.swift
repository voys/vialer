//
//  MissedCallNotification.swift
//  PIL
//
//  Created by Jeremy Norman on 26/08/2021.
//

import Foundation
import NotificationCenter

class MissedCallNotification {

    private let center: UNUserNotificationCenter
    
    init(center: UNUserNotificationCenter) {
        self.center = center
    }
        
    @available(iOS 12.0, *)
    func notify(call: Call) {
        log("Requesting notification authorization")
        
        center.getNotificationSettings { (settings) in
            if settings.authorizationStatus != .authorized {
                log("We do not have authorization to create a missed calls notification")
                return
            }
            
            self.findExistingNotification { existingNotification in
                let content = existingNotification != nil ? self.updateExistingNotification(call: call, notification: existingNotification!) : self.createNewNotification(call: call)
                let request = UNNotificationRequest(identifier: NotificationRequestIdentifiers.missedCalls.rawValue, content: content, trigger: nil)
                log("Adding notification with identifier: \(request.identifier)")
                self.center.add(request, withCompletionHandler: nil)
            }
        }
    }
    
    private func createNewNotification(call: Call) -> UNMutableNotificationContent {
        let content = buildBaseNotificationContent()
        content.title = String(format: NSLocalizedString("notification_missed_call_title", tableName: "MissedCall", comment: ""), 1)
        content.body = String(format: NSLocalizedString("notification_missed_call_subtitle", tableName: "MissedCall", comment: ""), call.remotePartyHeading, 1)
        return content
    }
    
    private func updateExistingNotification(call: Call, notification: UNNotification) -> UNMutableNotificationContent {
        let callsAmount = notification.missedCallsCount + 1
        let content = buildBaseNotificationContent(callsAmount: callsAmount)
        content.title = String(format: NSLocalizedString("notification_missed_call_title", tableName: "MissedCall", comment: ""), callsAmount)
        content.body = String(format: NSLocalizedString("notification_missed_call_subtitle", tableName: "MissedCall", comment: ""), "", callsAmount)
        return content
    }
    
    private func buildBaseNotificationContent(callsAmount: Int = 1)  -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.sound = UNNotificationSound.default
        content.badge = callsAmount as NSNumber
        content.userInfo[NotificationDataKeys.missedCallsCount.rawValue] = callsAmount
        return content
    }
    
    private func findExistingNotification(completion: @escaping  (UNNotification?) -> ()) {
        center.getDeliveredNotifications { notifications in
            completion(notifications.filter { notification in
                notification.request.identifier == NotificationRequestIdentifiers.missedCalls.rawValue
            }.first)
        }
    }
}

extension UNNotification {
    
    // The number of missed calls that this notification is currently tracking.
    var missedCallsCount: Int {
        request.content.userInfo[NotificationDataKeys.missedCallsCount.rawValue] as? Int ?? 0
    }
}

/// The identifiers for notification requests so they can be accessed by clients.
public enum NotificationRequestIdentifiers: String {
    case missedCalls = "pil-missed_calls_notification"
}

/// The keys that are contained within the [userInfo] object of the notifications.
public enum NotificationDataKeys: String {
    case missedCallsCount = "missedCallsCount"
}
