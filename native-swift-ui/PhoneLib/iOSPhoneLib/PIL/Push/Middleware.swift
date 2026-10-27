//
//  MiddlewareDelegate.swift
//  PIL
//
//  Created by Chris Kontos on 22/01/2021.
//

import Foundation
import PushKit

public protocol Middleware {

    func respond(payload: PKPushPayload, available: Bool, reason: UnavailableReason?)
    
    func tokenReceived(token: String)
    
    /// View the content of the push message before it is processed.
    func inspect(payload: PKPushPayload, type: PKPushType)
}

public extension Middleware {
    func respond(payload: PKPushPayload, available: Bool, reason: UnavailableReason? = nil) {
        respond(payload: payload, available: available, reason: reason)
    }
}
