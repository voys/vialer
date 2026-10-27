//
//  VoIPLibHelper.swift
//  PIL
//
//  Created by Jeremy Norman on 01/03/2021.
//

import Foundation

class VoIPLibHelper {
    private let voipLib: VoIPLib
    private let pil: PIL
    
    init(voipLib: VoIPLib, pil: PIL) {
        self.voipLib = voipLib
        self.pil = pil
    }

    /// Attempt to register if there are valid credentials.
    internal func register(callback: @escaping (Bool) -> Void) {
        if pil.auth == nil {
            pil.writeLog("There are no authentication credentials, not registering.")
            callback(false)
            return
        }
    
        pil.writeLog("Attempting registration...")
        
        voipLib.register { state in
            if state == .registered {
                self.pil.writeLog("Registration was successful!")
                callback(true)
            }
            else if state == .failed {
                self.pil.writeLog("Registration failed.")
                callback(false)
            }
        }
    }

}
