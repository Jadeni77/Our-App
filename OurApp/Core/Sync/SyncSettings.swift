import Foundation

/// When sync last worked.
///
/// There is deliberately no on/off key here any more. Being paired *is* the
/// switch — a second one would only ever be a way for the two to disagree — and
/// the privacy question it used to answer is now answered by
/// `LocalPeerService` refusing to advertise unless paired or pairing.
enum SyncSettings {
    static let lastSyncedKey = "sync.lastSyncedAt"

    static func lastSynced(_ defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: lastSyncedKey) as? Date
    }

    static func recordSync(at date: Date = .now, in defaults: UserDefaults = .standard) {
        defaults.set(date, forKey: lastSyncedKey)
    }
}
