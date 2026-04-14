import Foundation
import Security

/// Minimal Keychain wrapper for StatShot auth material.
///
/// Keys we persist (see `Keys` below):
///   - `statshot_user_id`       — backend user UUID (returned by /api/auth/apple)
///   - `statshot_user_email`    — email used at registration (may be nil after first SIWA)
///   - `statshot_apple_user_id` — Apple's stable user id (`sub` from the SIWA JWT)
///
/// All items are stored as `kSecClassGenericPassword` under a single service so
/// they can be inspected / deleted together. `save` replaces existing entries.
/// `load` returns `nil` on any error (missing item, keychain locked, decode
/// failure) rather than throwing — callers should treat absence as
/// "not signed in" and not crash the launch sequence.
enum Keychain {
    enum Keys {
        static let userId = "statshot_user_id"
        static let userEmail = "statshot_user_email"
        static let appleUserId = "statshot_apple_user_id"
    }

    private static let service = "com.statshot.app"

    /// Persist `value` at `key`. If an entry already exists it is overwritten.
    /// Returns `true` on success, `false` on any keychain error.
    @discardableResult
    static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        // Try update first (common case after first launch).
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return true
        }

        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            return addStatus == errSecSuccess
        }

        return false
    }

    /// Load the value for `key`. Returns `nil` if missing or on any error —
    /// by design: auth material going missing shouldn't crash the app, it
    /// should just drop the user back to the sign-in screen.
    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Remove a single key. Silently succeeds if the item doesn't exist.
    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
