//
//  .swift
//  Pods-SpindleSIPFramework_Example
//


import Foundation
import linphonesw

#if IOSPHONELIB_PRIVATE
import iOSPhoneLib_Private
#else
import LinphoneWrapper
#endif

public class VoIPLibCall:NSObject {
    public let callId = UUID()
    let linphoneCall: LinphoneCall
    
    public var remoteNumber: String {
        get {
            linphoneCall.remoteAddress?.username ?? ""
        }
    }
    
    public var displayName: String {
        get {
            linphoneCall.remoteAddress?.displayName ?? ""
        }
    }
    
    public var remoteEnvironment: String {
        get {
            linphoneCall.remoteAddress?.domain ?? ""
        }
    }
    
    public var state:VoipLibCallState {
        get {
            VoipLibCallState(rawValue: linphoneCall.state.rawValue) ?? .idle
        }
    }
    
    public var remotePartyId: String {
        get {
            linphoneCall.params?.getCustomHeader(headerName: "Remote-Party-ID") ?? ""
        }
    }
    
    public var pAssertedIdentity: String {
        get {
            linphoneCall.params?.getCustomHeader(headerName: "P-Asserted-Identity") ?? ""
        }
    }
    
    public var durationInSec:Int? {
        linphoneCall.duration
    }
    
    public var isIncoming:Bool {
        return linphoneCall.dir == .Incoming
    }
    
    public var direction: Direction {
        return linphoneCall.dir == .Incoming ? .inbound : .outbound
    }
    
    public var quality: Quality {
        return Quality(average: linphoneCall.averageQuality, current: linphoneCall.currentQuality)
    }
    
    /// This can be used to check if different  objects have the same linphone property.
    public var callHash: Int? {
        return linphoneCall.getCobject?.hashValue
    }
    
    public var reason: String {
        return String.init(describing: linphoneCall.reason)
    }
    
    public var wasMissed: Bool {
        guard let log = linphoneCall.callLog else {
            return false
        }
        
        let missedStatuses = [
            LinphoneCall.Status.Missed,
            LinphoneCall.Status.Aborted,
            LinphoneCall.Status.EarlyAborted,
        ]
        
        return log.dir == LinphoneCall.Dir.Incoming && missedStatuses.contains(log.status)
    }
    
    init?(linphoneCall: LinphoneCall) {
        guard linphoneCall.remoteAddress != nil else { return nil }
        self.linphoneCall = linphoneCall
    }
        
    /// Resumes a .
    /// The  needs to have been paused previously with `pause()`
    public func resume() throws {
        try linphoneCall.resume()
    }
    
    /// Pauses the .
    /// be played to the remote user. The only way to resume a paused  is to  `resume()`
    public func pause() throws {
        try linphoneCall.pause()
    }
}

extension VoIPLibCall {
    public static func == (lhs: VoIPLibCall, rhs: VoIPLibCall) -> Bool {
      return lhs.callId == rhs.callId
    }
}
