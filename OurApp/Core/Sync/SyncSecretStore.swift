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
        SecItemDelete(partnerQuery as CFDictionary)
    }

    /// Paired means **both** the secret and who it belongs to.
    ///
    /// It used to mean only the secret, which let a phone paired by an older
    /// build claim to be paired while being unable to name its partner — so
    /// co-op offered a Start button that silently did nothing. A state that
    /// says yes to a question the app can't act on is worse than saying no.
    static var isPaired: Bool { load() != nil && partnerAuthorID() != nil }

    // MARK: - Who we paired with

    /// The partner's `authorID`, kept beside the secret rather than in
    /// `UserDefaults`: the two are only meaningful together, and a phone that
    /// kept the secret through a reinstall but forgot who it belonged to would
    /// be paired with nobody.
    private static let partnerAccount = "couple.partnerAuthorID"

    private static var partnerQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrAccount as String: partnerAccount]
    }

    static func partnerAuthorID() -> String? {
        var query = partnerQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func savePartner(_ authorID: String) {
        SecItemDelete(partnerQuery as CFDictionary)
        var query = partnerQuery
        query[kSecValueData as String] = Data(authorID.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }
}
