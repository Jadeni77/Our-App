import Foundation

/// Whether sync is on, and when it last worked.
///
/// Off by default. Sync advertises this phone on the local network and answers
/// questions about your memories — that is not something to switch on for
/// somebody without asking, even on a network they own.
enum SyncSettings {
    static let enabledKey = "sync.localNetworkEnabled"
    static let lastSyncedKey = "sync.lastSyncedAt"

    static func lastSynced(_ defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: lastSyncedKey) as? Date
    }

    static func recordSync(at date: Date = .now, in defaults: UserDefaults = .standard) {
        defaults.set(date, forKey: lastSyncedKey)
    }
}
