//
// Created by Jeremy Norman on 18/02/2021.
//

import Foundation
import PushKit

class PushKitDelegate: NSObject {

    let pil = di.resolve(PIL.self)!
    let middleware: Middleware
    let voipRegistry: PKPushRegistry

    init(middleware: Middleware) {
        self.middleware = middleware
        voipRegistry = PKPushRegistry(queue: nil)
    }

    func registerForVoipPushes() {
        voipRegistry.delegate = self
        voipRegistry.desiredPushTypes = [.voIP]

        if let token = token {
            middleware.tokenReceived(token: token)
        }
    }
}

extension PushKitDelegate: PKPushRegistryDelegate {
    
    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        if type != .voIP {
            pil.writeLog("Received a non-VoIP push message. Halting processing.")
            return
        }
        
        let number = payload.dictionaryPayload[pil.app.pushKitPhoneNumberKey] as? String ?? ""
        let contact = pil.contacts.find(number: number, identifier: number)
        
        pil.iOSCallKit.reportIncomingCall(
            phoneNumber: number,
            callerName: contact?.name ?? payload.dictionaryPayload[pil.app.pushKitCallerNameKey] as? String ?? ""
        )
        
        Task {
            await self.handle(payload: payload, for: type)
        }
    }
    
    private func handle(payload: PKPushPayload, for type: PKPushType) async {
        await waitForAuthToBeConfigured()
        
        if !authIsConfigured {
            pil.writeLog("We have no authentication configured and so cannot accept this call")
            self.middleware.respond(payload: payload, available: false, reason: UnavailableReason.unableToRegister)
            return
        }
        
        self.middleware.inspect(payload: payload, type: type)
            
        pil.writeLog("Received a VoIP push message, starting incoming ringing.")
    
        if pil.calls.isInCall {
            pil.writeLog("Not taking call as we already have an active one!")
            self.middleware.respond(payload: payload, available: false, reason: UnavailableReason.inCall)
            return
        }
                        
        pil.start { success in
            self.pil.writeLog("PIL started with success=\(success), responding to middleware: \(success)")
            
            if success {
                self.middleware.respond(payload: payload, available: true)
            } else {
                self.middleware.respond(payload: payload, available: false, reason: UnavailableReason.unableToRegister)
            }
        }
    }
    
    var authIsConfigured: Bool { pil.auth != nil }
    
    /// Auth is configured in the AppDelegate, it is possible for a push notification to be received before this has properly
    /// been completed. In this case we will wait for up to 150 seconds for auth to become available before assuming it has failed.
    private func waitForAuthToBeConfigured() async {
        var attempts = 0
        
        // Awaiting for 150 attempts of 0.01 seconds = 1.5 seconds
        while !authIsConfigured && attempts <= 150 {
            try? await Task.sleep(nanoseconds: 10_000_000)
            attempts += 1
        }
    }

    var token: String? {
        get {
            guard let token = voipRegistry.pushToken(for: PKPushType.voIP) else {
                return nil
            }

            return String(apnsToken: token)
        }
    }

    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        let token = String(apnsToken: pushCredentials.token)
        log("Received a new APNS token: \(token)")

        middleware.tokenReceived(token: token)
    }
    
}

extension String {
    public init(apnsToken: Data) {
        self = apnsToken.map { String(format: "%.2hhx", $0) }.joined()
    }
}

public enum UnavailableReason {
    case inCall
    case unableToRegister
}
