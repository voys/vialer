//
//  Event.swift
//  PIL
//
//  Created by Jeremy Norman on 05/03/2021.
//

import Foundation

public enum Event {
    case outgoingCallStarted(state: CallSessionState)
    case incomingCallReceived(state: CallSessionState)
    case callEnded(state: CallSessionState)
    case callConnected(state: CallSessionState)
    case callDurationUpdated(state: CallSessionState)
    case audioStateUpdated(state: CallSessionState)
    case callStateUpdated(state: CallSessionState)
    
    case outgoingCallSetupFailed(reason: CallSetupFailedReason)
    case incomingCallSetupFailed(reason: CallSetupFailedReason)
    
    case attendedTransferStarted(state: CallSessionState)
    case attendedTransferAborted(state: CallSessionState)
    case attendedTransferConnected(state: CallSessionState)
    case attendedTransferEnded(state: CallSessionState)
}

public enum CallSetupFailedReason {
    case inCall
    case unknown
    case unableToRegister
    case rejectedByCallKit
}
