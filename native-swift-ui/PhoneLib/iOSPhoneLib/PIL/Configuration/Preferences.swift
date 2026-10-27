import Foundation

public struct Preferences: Equatable {
    public let useApplicationRingtone: Bool
    public let includesCallsInRecents: Bool
    
    public init(useApplicationRingtone: Bool = true, includesCallsInRecents: Bool = false) {
        self.useApplicationRingtone = useApplicationRingtone
        self.includesCallsInRecents = includesCallsInRecents
    }

    public static func ==(lhs: Self, rhs: Self) -> Bool {
        lhs.useApplicationRingtone == rhs.useApplicationRingtone && lhs.includesCallsInRecents == rhs.includesCallsInRecents
    }
}
