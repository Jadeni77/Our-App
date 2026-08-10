import Foundation

/// Who this install is, as far as records are concerned.
///
/// Generated once, never chosen. The previous design (P6) asked the owner which
/// half of the couple this phone was — a question sitting directly under a
/// Settings section already labelled "Me", and one nothing stopped both phones
/// answering the same way. A record tagged with the wrong half was
/// indistinguishable from a right one, so the app gated Daily Question and
/// Memories behind answering it, which made a redundant question a blocking one.
///
/// Comparing against a per-install id instead is symmetric, needs no setup, and
/// cannot be answered wrongly (P18). "Mine" is "matches this id"; everything
/// else is my love's.
///
/// **Known limit:** deleting and reinstalling regenerates the id, so memories
/// written before would read as the partner's. Restoring from a backup keeps
/// it, and CloudKit's own user record id supersedes this entirely when sync
/// lands — so it is a documented limit rather than a keychain problem to solve
/// now.
enum LocalAuthor {
    static let storageKey = "couple.authorID"

    /// Reads the id, generating and persisting one the first time. `defaults`
    /// is injectable so tests get a fresh install rather than the real one.
    static func id(defaults: UserDefaults = .standard) -> String {
        if let stored = defaults.string(forKey: storageKey), !stored.isEmpty {
            return stored
        }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: storageKey)
        return fresh
    }
}
