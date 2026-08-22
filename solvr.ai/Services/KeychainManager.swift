import Foundation
import Security

/// Storage for the user's Anthropic API key.
///
/// The Keychain is the only place a key is kept. An earlier version fell back to
/// `UserDefaults` when the Keychain write failed and still reported success,
/// which meant a secret could end up in a plaintext plist inside the app
/// container while the UI said "saved". A failure to store a credential securely
/// has to be a visible failure, not a silent downgrade.
///
/// The one concession: a key written to `UserDefaults` by an older build is
/// migrated into the Keychain on first read and then erased. Leaving it there to
/// rot would be worse than moving it.
enum KeychainManager {

    private static let service = "ai.solvr.apikey"
    private static let account = "anthropic-api-key"

    /// Only read from and deleted, never written. Present so a key stored by an
    /// older build can be rescued out of it.
    private static let legacyFallbackKey = "solvr_api_key_fallback"

    private static func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        #if targetEnvironment(macCatalyst)
        // Catalyst needs the data protection keychain explicitly, or the item
        // lands in the file-based keychain and reads back inconsistently.
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    /// Returns false if the key could not be stored securely. Callers must show
    /// that to the user rather than treating it as success.
    @discardableResult
    static func save(apiKey: String) -> Bool {
        delete()

        guard let data = apiKey.data(using: .utf8) else { return false }

        var query = baseQuery()
        query[kSecValueData as String] = data
        // After first unlock rather than always: the app has no reason to read
        // the key while the device is locked.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            // No plaintext fallback. Logged without the key, obviously.
            print("[Keychain] save failed, OSStatus \(status)")
            return false
        }
        return true
    }

    static func retrieve() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data,
           let key = String(data: data, encoding: .utf8) {
            return key
        }

        return migrateLegacyKeyIfPresent()
    }

    /// Move a key left in `UserDefaults` by an older build into the Keychain,
    /// then remove it. Returns the key either way -- failing to migrate is not a
    /// reason to lock someone out of their own app.
    private static func migrateLegacyKeyIfPresent() -> String? {
        guard let legacy = UserDefaults.standard.string(forKey: legacyFallbackKey),
              !legacy.isEmpty
        else { return nil }

        var query = baseQuery()
        query[kSecValueData as String] = Data(legacy.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecSuccess || status == errSecDuplicateItem {
            UserDefaults.standard.removeObject(forKey: legacyFallbackKey)
            print("[Keychain] migrated a key out of UserDefaults and removed it")
        } else {
            print("[Keychain] could not migrate legacy key, OSStatus \(status)")
        }
        return legacy
    }

    @discardableResult
    static func delete() -> Bool {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        UserDefaults.standard.removeObject(forKey: legacyFallbackKey)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    static var hasAPIKey: Bool {
        retrieve() != nil
    }
}
