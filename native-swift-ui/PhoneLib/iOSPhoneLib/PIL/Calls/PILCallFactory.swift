//
// Created by Jeremy Norman on 15/02/2021.
//

import Foundation

public class PILCallFactory {
    
    private let contacts: Contacts
    
    init(contacts: Contacts) {
        self.contacts = contacts
    }
    
    public func make(voipLibCall: VoIPLibCall?) -> Call? {
        guard let libraryCall = voipLibCall else {
            return nil
        }
        
        let remotePartyDetails = findRemotePartyDetails(call: libraryCall)
        
        return Call(
            remoteNumber: remotePartyDetails.0,
            displayName: remotePartyDetails.1,
            state: convertCallState(state: libraryCall.state),
            direction: libraryCall.direction == .inbound ? .inbound : .outbound,
            duration: libraryCall.durationInSec ?? 0,
            isOnHold: (libraryCall.state == .pausedByRemote || libraryCall.state == .paused),
            uuid: UUID.init(),
            mos: libraryCall.quality.average,
            currentMos: libraryCall.quality.current,
            contact: contacts.find(call: libraryCall),
            reason: libraryCall.reason
        )
    }
    
    private func findRemotePartyDetails(call: VoIPLibCall) -> (String, String) {
        if !call.pAssertedIdentity.isEmpty {
            let value = extractHeaderValue(rawHeader: call.pAssertedIdentity)
            return (value.0, value.1)
        }
        
        if !call.remotePartyId.isEmpty {
            let value = extractHeaderValue(rawHeader: call.remotePartyId)
            return (value.0, value.1)
        }
        
        return (call.remoteNumber, call.displayName ?? "")
    }
    
    private func extractHeaderValue(rawHeader: String) -> (String, String) {
        let numberPattern = "<?sip:(.+)@"
        let namePattern = "^\"(.+)\" "
    
        return (
            extractCaptureGroup(target: rawHeader, pattern: numberPattern),
            extractCaptureGroup(target: rawHeader, pattern: namePattern)
        )
    }
    
    private func extractCaptureGroup(target: String, pattern: String) -> String {
        let regex = try! NSRegularExpression(pattern: pattern)
        let result = regex.matches(in: target, range: NSMakeRange(0, target.utf16.count))
        
        if result.isEmpty {
            return ""
        }
        
        let nsRange = result[0].range(at: 1)
        
        if let range = Range(nsRange, in: target) {
            return String(target[range])
        }
        
        return ""
    }
    
    private func convertCallState(state: VoipLibCallState) -> CallState {
        switch state {
        case .idle:
            return .initializing
        case .incomingReceived, .outgoingDidInitialize, .outgoingProgress, .outgoingRinging, .incomingReceivedFromPush:
            return .ringing
        case .connected, .streamsRunning, .outgoingEarlyMedia, .earlyUpdatedByRemote, .earlyUpdating, .incomingEarlyMedia, .pausing, .resuming, .referred, .updatedByRemote, .updating:
            return .connected
        case .paused:
            return .heldByLocal
        case .pausedByRemote:
            return .heldByRemote
        case .error:
            return .error
        case .ended, .released:
            return .ended
        }
    }
}

