//
// Created by Jeremy Norman on 15/02/2021.
//

import Foundation

public struct ApplicationSetup {
    public let middleware: Middleware?
    public let requestCallUi: () -> Void
    public let userAgent: String
    public let logDelegate: LogDelegate?
    public let notifyOnMissedCall: Bool
    public let pushKitPhoneNumberKey: String
    public let pushKitCallerNameKey: String
    public let ringtonePath: String
    
    public init(
        middleware: Middleware? = nil,
        requestCallUi: @escaping () -> Void,
        userAgent: String = "iOS PIL",
        logDelegate: LogDelegate? = nil,
        notifyOnMissedCall: Bool = true,
        pushKitPhoneNumberKey: String = "phonenumber",
        pushKitCallerNameKey: String = "caller_id",
        ringtonePath: String = ""
    ) {
        self.middleware = middleware
        self.userAgent = userAgent
        self.requestCallUi = requestCallUi
        self.logDelegate = logDelegate
        self.notifyOnMissedCall = notifyOnMissedCall
        self.pushKitPhoneNumberKey = pushKitPhoneNumberKey
        self.pushKitCallerNameKey = pushKitCallerNameKey
        self.ringtonePath = ringtonePath
    }
}
