import Foundation
import Security

/// The paired secret, in the Keychain rather than `UserDefaults`.
///
/// It is the one value in this app that is genuinely a credential: anything
/// holding it can ask this phone for every memory it has. `UserDefaults` is a
/// plist in the app container, so the Keychain is the right home even though it
/// costs a few more lines.
enum SyncSecretStore {
    private static let account = "couple.syncSecret"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrAccount as String: account]
    }

    static func load() -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    static func save(_ secret: Data) {
        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = secret
        // After-first-unlock rather than when-unlocked: a sync tick can fire
        // while the phone is locked in a pocket, and a secret it cannot read is
        // a sync that silently stops.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    static var isPaired: Bool { load() != nil }
}
