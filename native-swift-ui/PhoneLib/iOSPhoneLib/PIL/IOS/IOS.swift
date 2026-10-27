//
//  IOS.swift
//  PIL
//
//  Created by Jeremy Norman on 06/03/2021.
//

import Foundation
import CallKit
import UIKit

public class IOS {
    
    private let pil: PIL
    
    init(pil: PIL) {
        self.pil = pil
    }
    
    public func startListeningForSystemNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(willEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil)
    }
    
    @objc func willEnterForeground() {
        pil.writeLog("Application has entered the foreground")
        
        if pil.calls.activeCall != nil {
            pil.app.requestCallUi()
        }
        
        pil.start()
    }
    
    @objc func didBecomeActive() {
        UIApplication.shared.applicationIconBadgeNumber = 0
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
    
    @objc func didEnterBackground() {
        pil.writeLog("Application has entered the background")
    }
}
