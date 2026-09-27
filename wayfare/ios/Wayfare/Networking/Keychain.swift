import Foundation
import Security

/// A minimal generic-password Keychain wrapper for small strings (the session token).
enum Keychain {
    private static let service = "com.wayfare.app"

    enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
    }

    static func set(_ value: String, for account: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            // Readable after first unlock, so a background push can still sync.
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func get(_ account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// Holds the bearer token in memory, backed by the Keychain.
@MainActor
final class TokenStore {
    private static let account = "sessionToken"
    private(set) var token: String?
    private let persists: Bool

    init() {
        persists = true
        token = Keychain.get(Self.account)
    }

    /// For previews and tests: never touches the Keychain.
    init(inMemoryToken: String?) {
        persists = false
        token = inMemoryToken
    }

    func save(_ newToken: String) {
        token = newToken
        if persists {
            try? Keychain.set(newToken, for: Self.account)
        }
    }

    func clear() {
        token = nil
        if persists {
            Keychain.delete(Self.account)
        }
    }
}
