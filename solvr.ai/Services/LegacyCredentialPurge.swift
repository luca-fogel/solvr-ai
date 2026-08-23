import Foundation
import Security

/// Erases credentials left behind by builds that had a hosted backend.
///
/// Deleting `KeychainManager` removes the app's ability to *use* a key. It does
/// not remove the key: an install upgrading from a build that stored one would
/// keep an Anthropic API key in its keychain indefinitely, owned by an app that
/// no longer has any code to read it. "No trace of the key" has to mean the
/// devices too, so this runs once and takes the old items with it.
///
/// Three things are removed, because the key reached three places over the app's
/// life:
///
/// - both accounts under the `ai.solvr.apikey` service (the Anthropic key and
///   the local-server bearer token, which were split apart in an earlier fix);
/// - `solvr_api_key_fallback` in `UserDefaults`, written in plaintext by a
///   version of `KeychainManager` that silently fell back when the keychain
///   write failed and then reported success;
/// - the backend/model/server preferences, which now select nothing.
///
/// Deliberately not gated on "did this install ever have a key". The queries are
/// cheap, `errSecItemNotFound` is the expected answer on a clean install, and a
/// purge that can be skipped by a wrong guess is worse than one that always runs.
enum LegacyCredentialPurge {

    private static let didRunKey = "legacyCredentialPurgeDidRun"
    private static let service = "ai.solvr.apikey"
    private static let accounts = ["anthropic-api-key", "local-server-token"]
    private static let staleDefaults = [
        "solvr_api_key_fallback",  // the plaintext fallback
        "selectedBackend",         // there is one backend now
        "selectedModel",           // the system provides the model
        "maxTokens",               // on-device context is fixed at 4096
        "localServerURL",
        "localServerModel",
    ]

    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didRunKey) else { return }

        for account in accounts {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(query as CFDictionary)
        }

        for key in staleDefaults {
            defaults.removeObject(forKey: key)
        }

        defaults.set(true, forKey: didRunKey)
    }
}
