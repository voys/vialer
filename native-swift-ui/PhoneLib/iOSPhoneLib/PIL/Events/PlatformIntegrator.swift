//
//  PlatformIntegrator.swift
//  PIL
//
//  Created by Chris Kontos on 03/08/2021.
//

import Foundation
import CallKit	

// Listens to PIL events and performs the necessary actions in the Callkit.
class PlatformIntegrator: PILEventDelegate {
    
    private let pil: PIL
    private let missedCallNotification: MissedCallNotification
    private let callFactory: PILCallFactory
    
    init(pil: PIL, missedCallNotification: MissedCallNotification, callFactory: PILCallFactory) {
        self.pil = pil
        self.missedCallNotification = missedCallNotification
        self.callFactory = callFactory
    }
    
    func onEvent(event: Event) {
        switch event {
            case .callDurationUpdated(_): break
            default: self.pil.writeLog("PlatformIntegrator received \(event) event")
        }
        
        handle(event: event)
    }
    
    private func handle(event: Event) {
        
        switch event {
            case .outgoingCallStarted:
                pil.iOSCallKit.reportOutgoingCallConnecting()
                pil.app.requestCallUi()
            case .callEnded(_):
                pil.audio.unmute()
                pil.iOSCallKit.endAllCalls()
                fallthrough
            case .attendedTransferAborted,
                 .attendedTransferEnded:
                pil.calls.transferSession = nil
            case .callConnected:
                callKitUpdateCurrentCall()
                pil.app.requestCallUi()
            case.attendedTransferConnected,
                .incomingCallReceived,
                .callStateUpdated:
                callKitUpdateCurrentCall()
            default:
                return
        }
    }
    
    internal func notifyIfMissedCall(call: VoIPLibCall) {
        if !call.wasMissed { return }
        
        if !pil.app.notifyOnMissedCall { return }
        
        if #available(iOS 12.0, *) {
            if let call = callFactory.make(voipLibCall: call) {
                missedCallNotification.notify(call: call)
            }
        }
    }
    
    func callKitUpdateCurrentCall() {
        if let call = pil.calls.activeCall {
            pil.iOSCallKit.updateCall(call: call)
        }
    }
}
