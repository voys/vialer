import Foundation
import Security

/// Keeps credentials in the Keychain for both Flutter and native code.
class SecureStorage: NSObject, NativeSecureStorage {
    private enum Key: String, CaseIterable {
        case apiToken = "api_token"
        case sipPassword = "sip_password"
    }

    private let service = "\(Bundle.main.bundleIdentifier!).secure-storage"

    /// Values are nil when missing, or before the first unlock after a reboot.
    var credentials: Credentials {
        Credentials(apiToken: try? read(.apiToken), sipPassword: try? read(.sipPassword))
    }

    func read() async throws -> Credentials {
        credentials
    }

    func write(credentials: Credentials) async throws {
        if let apiToken = credentials.apiToken {
            try persist(apiToken, for: .apiToken)
        }
        if let sipPassword = credentials.sipPassword {
            try persist(sipPassword, for: .sipPassword)
        }
    }

    func clear() async throws {
        for key in Key.allCases {
            let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw keychainError(status)
            }
        }
    }

    func keySecurityLevel() async throws -> String? {
        nil
    }

    private func baseQuery(for key: Key) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }

    private func read(_ key: Key) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }

        guard status == errSecSuccess, let data = result as? Data else {
            throw keychainError(status)
        }

        return String(data: data, encoding: .utf8)
    }

    private func persist(_ value: String, for key: Key) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            // Incoming calls must be able to read credentials while the device is locked.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        var status = SecItemUpdate(baseQuery(for: key) as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            status = SecItemAdd(baseQuery(for: key).merging(attributes) { $1 } as CFDictionary, nil)
        }

        guard status == errSecSuccess else { throw keychainError(status) }
    }

    private func keychainError(_ status: OSStatus) -> PigeonError {
        PigeonError(code: "keychain", message: "OSStatus \(status)", details: nil)
    }
}
