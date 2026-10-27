//
// Created by Jeremy Norman on 15/02/2021.
//

import Foundation

public enum CallState {
    case initializing
    case ringing
    case connected
    case heldByLocal
    case heldByRemote
    case ended
    case error
}
