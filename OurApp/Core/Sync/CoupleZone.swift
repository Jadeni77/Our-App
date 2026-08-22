import CloudKit
import Foundation
import OSLog

/// The one CloudKit zone the couple shares, and the handshake that joins it.
///
/// **A custom zone, because the default zone cannot be shared.** Everything the
/// two of you write lives here; each phone's own private mirror — the backup
/// proven on the owner's phone on 2026-08-13 — is untouched and stays where it
/// is.
///
/// The handshake replaces the pairing code. One person shares, the other opens
/// the link once, and both ids are exchanged in the process exactly as pairing
/// already does. After that it is invisible forever.
@MainActor
enum CoupleZone {
    static let containerID = "iCloud.com.jadeni77.OurApp"
    static let zoneName = "Couple"
    static let shareTitle = "Our App"

    static var container: CKContainer { CKContainer(identifier: containerID) }

    /// The owner's zone id — the one *this* phone created, if it is the sharer.
    static var ownedZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    /// Which zone to actually sync against.
    ///
    /// **Not a guess.** The sharer syncs against the zone it owns in its
    /// private database; the accepter syncs against the *same* zone as it
    /// appears in its shared database, under the owner's name. Getting this
    /// backwards means two people each writing happily into a zone the other
    /// never reads — which is the exact failure this whole session has been
    /// about, so it is derived from what CloudKit reports rather than assumed.
    static func syncTarget() async -> (database: CKDatabase, zoneID: CKRecordZone.ID)? {
        // A zone in the shared database means someone shared with us: use it.
        if let shared = try? await container.sharedCloudDatabase.allRecordZones(),
           let theirs = shared.first(where: { $0.zoneID.zoneName == zoneName }) {
            return (container.sharedCloudDatabase, theirs.zoneID)
        }
        // Otherwise we are the owner, or nobody has shared yet — either way our
        // own zone is the right one to write into.
        return (container.privateCloudDatabase, ownedZoneID)
    }

    /// Creates the zone and its share, and hands back a link to send.
    ///
    /// Idempotent: asked twice, it returns the existing share rather than
    /// making a second one, because two shares on one zone is a pair of people
    /// who each think they invited the other.
    static func makeShare() async throws -> CKShare {
        let database = container.privateCloudDatabase
        let zone = CKRecordZone(zoneID: ownedZoneID)
        _ = try? await database.modifyRecordZones(saving: [zone], deleting: [])

        if let existing = try? await database.record(for: shareRecordID) as? CKShare {
            return existing
        }

        let share = CKShare(recordZoneID: ownedZoneID)
        share[CKShare.SystemFieldKey.title] = shareTitle as CKRecordValue
        // Read-write, and only for people explicitly invited: this is a
        // two-person app and the link is not something to leave open.
        share.publicPermission = .none
        let (results, _) = try await database.modifyRecords(saving: [share], deleting: [])
        for (_, result) in results {
            if case .success(let record) = result, let saved = record as? CKShare { return saved }
        }
        throw CKError(.internalError)
    }

    private static var shareRecordID: CKRecord.ID {
        CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: ownedZoneID)
    }

    /// Accepts an invitation the other phone sent.
    ///
    /// Called from the app delegate, which is the only place iOS hands this to
    /// us. Accepting twice is fine — CloudKit treats it as a no-op — which
    /// matters because a link can be opened more than once.
    static func accept(_ metadata: CKShare.Metadata) async throws {
        _ = try await container.accept(metadata)
        Logger(subsystem: "OurApp", category: "cloudkit").info("accepted the couple share")
    }
}
