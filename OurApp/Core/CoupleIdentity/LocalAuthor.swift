import Foundation
import Security

/// Where this install's author id is kept. A seam because the Keychain is
/// process-wide: two "fresh installs" in one test process would otherwise share
/// an identity, and the test that proves two phones get different ids would
/// pass for the wrong reason.
protocol AuthorIDStorage: Sendable {
    func load() -> String?
    func save(_ id: String)
}

struct KeychainAuthorIDStorage: AuthorIDStorage {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrAccount as String: "couple.authorID"]
    }

    func load() -> String? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ id: String) {
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = Data(id.utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(insert as CFDictionary, nil)
    }
}

/// Who this install is, as far as records are concerned.
///
/// Generated once, never chosen. The previous design (P6) asked the owner which
/// half of the couple this phone was — a question sitting directly under a
/// Settings section already labelled "Me", and one nothing stopped both phones
/// answering the same way. Comparing against a per-install id instead is
/// symmetric, needs no setup, and cannot be answered wrongly (P18).
///
/// **It lives in the Keychain**, which survives deleting the app. It used to
/// live in `UserDefaults`, which does not — so a reinstall generated a fresh id
/// and every record the phone had ever written suddenly read as the partner's.
/// P18 logged that as a known limit; it stopped being acceptable the moment
/// "delete the app and keep our progress" became a requirement.
enum LocalAuthor {
    /// The old home. Read once, to carry an existing install across; never
    /// written again, and deliberately not deleted — a migration that removes
    /// what it reads is how the anniversary went missing on every launch (H14).
    static let legacyDefaultsKey = "couple.authorID"

    /// Injected rather than global. A mutable static would be simpler, but
    /// Swift Testing runs suites in parallel — one suite swapping the store
    /// while another is resolving its identity is a flake that would appear
    /// once a month and never reproduce.
    static func id(defaults: UserDefaults = .standard,
                   storage: AuthorIDStorage = KeychainAuthorIDStorage()) -> String {
        if let stored = storage.load(), !stored.isEmpty { return stored }
        // An install that predates the Keychain keeps its identity rather than
        // orphaning everything it has already written.
        if let legacy = defaults.string(forKey: legacyDefaultsKey), !legacy.isEmpty {
            storage.save(legacy)
            return legacy
        }
        let fresh = UUID().uuidString
        storage.save(fresh)
        return fresh
    }
}
