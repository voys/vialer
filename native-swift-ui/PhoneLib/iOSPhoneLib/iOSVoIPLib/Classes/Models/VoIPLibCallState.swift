//
//  VoIPLibCallState.swift
//  VoIPLib
//
//  Created by Fabian Giger on 02/07/2020.
//

import Foundation

///LinphoneVoIPLibCallState enum represents the different states a VoIPLibCall can reach into.
public enum VoipLibCallState:Int {
    case idle = 0
    case incomingReceived = 1
    case incomingReceivedFromPush = 2
    case outgoingDidInitialize = 3
    case outgoingProgress = 4
    case outgoingRinging = 5
    case outgoingEarlyMedia = 6
    case connected = 7
    case streamsRunning = 8
    case pausing = 9
    case paused = 10
    case resuming = 11
    case referred = 12
    case error = 13
    case ended = 14
    case pausedByRemote = 15
    case updatedByRemote = 16
    case incomingEarlyMedia = 17
    case updating = 18
    case released = 19
    case earlyUpdatedByRemote = 20
    case earlyUpdating = 21
}
