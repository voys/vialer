//
//  VoIPLibCallDelegate.swift
//  VoIPLib
//
//  Created by Fabian Giger on 02/07/2020.
//

import Foundation

public protocol VoIPLibCallDelegate: AnyObject {
    ///  An incoming VoIPLibCall has been received by the library.
    ///
    /// - Parameters:
    ///     - incomingVoIPLibCall: The incoming VoIPLibCall
    func incomingCallReceived(_ call: VoIPLibCall)
    
    /// VoIPLibCallback when there's a new outgoing VoIPLibCall.
    ///
    /// - Parameters:
    ///     - VoIPLibCall: The VoIPLibCall
    func outgoingCallCreated(_ call: VoIPLibCall)
    
    /// VoIPLibCallback when a VoIPLibCall is connected.
    ///
    /// - Parameters:
    ///     - VoIPLibCall: The VoIPLibCall
    func callConnected(_ call: VoIPLibCall)
    
    /// VoIPLibCallback when a VoIPLibCall ended.
    ///
    /// - Parameters:
    ///     - VoIPLibCall: The VoIPLibCall
    func callEnded(_ call: VoIPLibCall)
    
    /// VoIPLibCallback when a VoIPLibCall has been updated. This is more generic VoIPLibCallback. It's only used when there not a state specific VoIPLibCallback.
    ///
    /// - Parameters:
    ///     - VoIPLibCall: The VoIPLibCall
    ///     - message: The message from the server.
    func callUpdated(_ call: VoIPLibCall, message: String)
    
    /// When the VoIPLibCall object has been released.
    ///
    /// - Parameters:
    ///     - VoIPLibCall: The VoIPLibCall
    func callReleased(_ call:VoIPLibCall)
    
    /// An Attended Transfer has completed and the two VoIPLibCalls have been merged, this will occur before receiving the ended and released events.
    ///
    /// - Parameters:
    ///     - VoIPLibCall: The VoIPLibCall
    func attendedTransferMerged(_ call: VoIPLibCall)
}
