//
//  Container.swift
//  PIL
//
//  Created by Jeremy Norman on 15/02/2021.
//

import Foundation
import CallKit
import AVFoundation
import Swinject
import UserNotifications

// Resolves the current preferences from the [PIL] that doesn't require depending on the whole
// [PIL] object.

var register: (Container) -> Container = {
    
    $0.register(PIL.self) { _ in
        PIL.shared!
    }.inObjectScope(.container)
        
    $0.register(CallActions.self) { c in
        CallActions(
            controller: CXCallController(),
            pil: c.resolve(PIL.self)!,
            voipLib: c.resolve(VoIPLib.self)!,
            systemTones: c.resolve(SystemTones.self)!
        )
    }.inObjectScope(.container)
    
    $0.register(EventsManager.self) { c in
        EventsManager(
            pil: c.resolve(PIL.self)!,
            calls: c.resolve(Calls.self)!
        )
    }.inObjectScope(.container)
    
    $0.register(Calls.self) { c in
        Calls(factory: c.resolve(PILCallFactory.self)!)
    }.inObjectScope(.container)
    
    $0.register(AudioManager.self) { c in AudioManager(
        pil: c.resolve(PIL.self)!,
        voipLib: c.resolve(VoIPLib.self)!,
        audioSession: AVAudioSession.sharedInstance(),
        callActions: c.resolve(CallActions.self)!
    ) }.inObjectScope(.container)
    
    $0.register(Contacts.self) { _ in Contacts() }.inObjectScope(.container)
    
    $0.register(PILCallFactory.self) { c in
        PILCallFactory(contacts: c.resolve(Contacts.self)!)
    }.inObjectScope(.container)
    
    $0.register(VoIPLib.self) { _ in VoIPLib.shared }.inObjectScope(.container)
    
    $0.register(VoipLibEventTranslator.self) { c in
        VoipLibEventTranslator(pil: c.resolve(PIL.self)!)
    }.inObjectScope(.container)
    
    $0.register(PlatformIntegrator.self) { c in
        PlatformIntegrator(
            pil: c.resolve(PIL.self)!,
            missedCallNotification: c.resolve(MissedCallNotification.self)!,
            callFactory: c.resolve(PILCallFactory.self)!
        )
    }.inObjectScope(.container)
    
    $0.register(IOS.self) { c in
        IOS(pil: c.resolve(PIL.self)!)
    }.inObjectScope(.container)
    
    $0.register(VoIPLibHelper.self) { c in
        VoIPLibHelper(
            voipLib: c.resolve(VoIPLib.self)!,
            pil: c.resolve(PIL.self)!
        )
    }.inObjectScope(.container)
    
    $0.register(IOSCallKit.self) { c in
        IOSCallKit(
            pil: c.resolve(PIL.self)!,
            voipLib: c.resolve(VoIPLib.self)!
        )
    }.inObjectScope(.container)
    
    $0.register(MissedCallNotification.self) { c in
        MissedCallNotification(
            center: UNUserNotificationCenter.current()
        )
    }.inObjectScope(.container)

    $0.register(SystemTones.self) { _ in
        SystemTones()
    }.inObjectScope(.container)

    return $0
}




