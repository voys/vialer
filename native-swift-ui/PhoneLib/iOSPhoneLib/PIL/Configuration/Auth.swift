//
//  Auth.swift
//  PIL
//
//  Created by Chris Kontos on 17/12/2020.
//

import Foundation

public struct Auth: Equatable {
    public let username: String
    public let password: String
    public let domain: String
    public let port: Int
    public let secure: Bool

    public var isValid: Bool {
        get {
            !username.isEmpty && !password.isEmpty && !domain.isEmpty && port != 0
        }
    }

    public init(username: String, password: String, domain: String, port: Int, secure: Bool) {
        self.username = username
        self.password = password
        self.domain = domain
        self.port = port
        self.secure = secure
    }

    public static func ==(lhs: Self, rhs: Self) -> Bool {
        lhs.username == rhs.username && lhs.password == rhs.password && lhs.domain == rhs.domain && lhs.port == rhs.port && lhs.secure == rhs.secure
    }
}
