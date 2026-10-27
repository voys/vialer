//
// Created by Jeremy Norman on 18/02/2021.
//

import Foundation

public typealias LogListener = (String) -> Void

struct VoIPLibConfig {
    init(callDelegate: VoIPLibCallDelegate, logListener: @escaping LogListener) {
        self.callDelegate = callDelegate
        self.logListener = logListener
    }
    
    let callDelegate: VoIPLibCallDelegate
    let logListener: LogListener
}
