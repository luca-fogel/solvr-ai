import Foundation
import Security

enum KeychainManager {

    private static let service = "ai.solvr.apikey"
    private static let account = "anthropic-api-key"
    private static let fallbackKey = "solvr_api_key_fallback"

    static func save(apiKey: String) -> Bool {
        delete()

        guard let data = apiKey.data(using: .utf8) else { return false }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        #if targetEnvironment(macCatalyst)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecSuccess {
            return true
        } else {
            print("[Keychain] Save failed with status: \(status). Falling back to UserDefaults.")
            UserDefaults.standard.set(apiKey, forKey: fallbackKey)
            return true
        }
    }

    static func retrieve() -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        #if targetEnvironment(macCatalyst)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess,
           let data = item as? Data,
           let key = String(data: data, encoding: .utf8) {
            return key
        }

        // Fallback: check UserDefaults
        if let fallback = UserDefaults.standard.string(forKey: fallbackKey), !fallback.isEmpty {
            return fallback
        }

        return nil
    }

    @discardableResult
    static func delete() -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        #if targetEnvironment(macCatalyst)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif

        let status = SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: fallbackKey)

        return status == errSecSuccess || status == errSecItemNotFound
    }

    static var hasAPIKey: Bool {
        retrieve() != nil
    }
}
