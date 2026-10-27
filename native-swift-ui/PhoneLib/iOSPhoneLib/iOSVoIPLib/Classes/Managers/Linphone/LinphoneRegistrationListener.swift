import Foundation
import linphonesw

#if IOSPHONELIB_PRIVATE
import iOSPhoneLib_Private
#else
import LinphoneWrapper
#endif

internal class LinphoneRegistrationListener : CoreDelegate {
    
    /**
     * The amount of time to wait before determining registration has failed.
     */
    private let registrationTimeoutSecs: Double = 5
    
    /**
     * The time that we will wait before executing the method again to clean-up.
     */
    private let cleanUpDelaySecs: Double = 1
    
    /**
     * It is sometimes possible that a failed registration will occur before a successful one
     * so we will track the time of the first registration update before determining it has
     * failed.
     */
    private var startTime: Double? = nil
    
    private var currentTime: Double {
        get {
            return NSDate().timeIntervalSince1970
        }
    }
    
    private var timer: Timer? = nil
    
    private let manager: LinphoneManager

    init(manager: LinphoneManager) {
        self.manager = manager
    }

    func onAccountRegistrationStateChanged(core: Core, account: Account, state: LinphoneRegistrationState, message: String) {
        log("Received registration state change: \(state.rawValue), message: \(message)")

        if manager.handleUnregisterStateChange(account: account, state: state, message: message) {
            return
        }
        
        let callbacks = manager.registrationCallbacks
        
        if callbacks.isEmpty {
            log("No call backs exist, registration change does nothing.")
            return
        }
        
        // If the registration was successful, just immediately invoke the callback and reset
        // all timers.
        if state == LinphoneRegistrationState.Ok {
            log("Successful, resetting timers.")
            manager.registrationCallbacks = []
            callbacks.invoke(state: RegistrationState.registered)
            reset()
            return
        }
        
        // If there is no start time, we want to set it to begin the time.
        let startTime = (self.startTime != nil ? self.startTime : {
            let startTime = currentTime
            self.startTime = startTime
            log("Started registration timer: \(startTime).")
            return startTime
        }())!
        
        if hasExceededTimeout(startTime) {
            manager.registrationCallbacks = []
            manager.unregister()
            log("Registration timeout has been exceeded, registration failed.")
            callbacks.invoke(state: RegistrationState.failed)
            reset()
            return
        }
        
        // Queuing call of this method so we ensure that the callback is eventually invoked
        // even if there are no future registration updates.
        timer = Timer.scheduledTimer(withTimeInterval: cleanUpDelaySecs, repeats: false, block: { _ in
            self.onAccountRegistrationStateChanged(
                core: core,
                account: account,
                state: state,
                message: "Automatically called to ensure callback is executed"
            )
        })
    }
    
    private func hasExceededTimeout(_ startTime: Double) -> Bool {
        return (startTime + registrationTimeoutSecs) < currentTime
    }
    
    private func reset() {
        startTime = nil
        timer?.invalidate()
    }
}

extension Array {
    func invoke(state: RegistrationState) {
        filter { element in
            element is RegistrationCallback
        }.forEach { element in
            let callback = element as! RegistrationCallback
            callback(state)
        }
    }
}
