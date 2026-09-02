import Foundation
import SwiftData

/// Every picture the two of you have, whether or not it is filed.
@MainActor
enum PhotoLibrary {
    /// Gives a record to any asset that has one only by being mentioned in a
    /// memory.
    ///
    /// **Idempotent, and run on every appear** — the same shape as the profile
    /// seed. A migration step that runs once is a migration step that can
    /// half-run; deriving the missing rows instead means the library is right
    /// after any launch, including the one where the last attempt was killed.
    ///
    /// Takes no author: every row it creates is credited to the memory the
    /// asset came in on. It used to take one and never read it, which reads as
    /// "the seeder decides authorship" and is the opposite of what happens.
    ///
    /// **Sets `takenAt` only on rows it creates here, never on a row that
    /// already exists.** `Photo` has no field for "never dated" versus
    /// "deliberately cleared" — both are `nil` — so a pass that backfills a
    /// date onto any existing row with a nil `takenAt` cannot tell those
    /// apart, and silently puts a date back the moment a hand-set `takenAt`
    /// is cleared, since the next appear of `MemoriesView` reruns this. This
    /// used to backfill existing rows too, for the transitional case of a row
    /// that predated `takenAt` existing at all; that need is gone (every row
    /// created since gets a date here, and one that arrives by sync carries
    /// `takenAt` in its own envelope), and what the backfill uniquely did
    /// after that was undo a clear. The cost: a `Photo` row old enough to
    /// predate this rule, and never dated by hand, stays under "Sometime"
    /// until someone dates it — which is exactly where an undated photo
    /// belongs (H23), not a guess this seed should make for them.
    static func seed(in context: ModelContext) {
        guard let memories = try? context.fetch(
            FetchDescriptor<Memory>(predicate: Memory.visible)),
              let existing = try? context.fetch(FetchDescriptor<Photo>())
        else { return }

        // **When each picture was taken, as far as the memories know.**
        //
        // Without this, `takenAt` stayed nil forever and `sortDate` fell back
        // to `addedAt` — *the moment this phone happened to run the seed* — so
        // the two libraries put the same pictures in different orders and
        // neither order meant anything. A memory's `day` is a floating civil
        // day both phones already agree on (H8), which is exactly the kind of
        // date that can be sorted by on two devices.
        //
        // The **earliest** day among the memories naming an asset, not the
        // first one the fetch happened to return: a picture can sit in two
        // memories, and "whichever came back first" is precisely the
        // phone-dependent answer this is here to get rid of. An undated memory
        // contributes nothing — a guessed date would be wrong forever, which is
        // worse than none (H23).
        var takenAt: [String: Date] = [:]
        for memory in memories {
            guard let day = memory.day else { continue }
            for asset in memory.photoIDs where takenAt[asset].map({ day < $0 }) ?? true {
                takenAt[asset] = day
            }
        }

        // Intentionally unfiltered: we include tombstoned Photos in `known` to avoid
        // resurrecting them. A user who deleted a photo should not see it reappear
        // after an app update. `all(in:)` filters on `Photo.visible`, so they stay
        // known here and invisible there.
        var known = Set(existing.map(\.assetID))
        var changed = false
        for memory in memories {
            for asset in memory.photoIDs where !known.contains(asset) {
                known.insert(asset)
                // Credited to whoever wrote the memory it came in, not to
                // whoever happens to be holding the phone during the seed.
                // A deleted memory takes its files with it, so we only seed from
                // visible memories — this way we never create records for bytes
                // that no longer exist.
                context.insert(Photo(assetID: asset, authorID: memory.authorID,
                                     takenAt: takenAt[asset]))
                changed = true
            }
        }

        if changed { try? context.save() }
    }

    /// Tombstones the library rows for assets a deleted memory took its files
    /// with — and **only** for assets no other visible memory still names.
    ///
    /// Called from `MemoryDetailView.delete()`, which is the one place in the
    /// app that destroys bytes. Without it, All photos keeps a tile per lost
    /// asset: a placeholder that can never load, indistinguishable from "hasn't
    /// synced yet", with no photo-delete anywhere to clear it, and still
    /// tappable in the picker so it can be filed into an album as a permanently
    /// blank square.
    ///
    /// **This is deliberately not reconciliation.** The tempting version —
    /// "tombstone any `Photo` no visible `Memory` names" inside `seed` — is a
    /// data-loss bug, not a tidier fix: `Photo` and `Memory` are independent
    /// records, so a photo legitimately arrives before the memory that mentions
    /// it, and a sticky tombstone written in that window deletes the picture
    /// from *both* phones forever. Retiring only what a delete just orphaned
    /// touches nothing that is merely early.
    ///
    /// Call it **after** the memory's own tombstone is durable: the survivor
    /// scan reads `Memory.visible`, so a memory still visible counts itself as
    /// a reason to keep its photos. Calling it early therefore retires nothing,
    /// which is the harmless direction.
    static func retire(assets: [String], in context: ModelContext) {
        guard !assets.isEmpty else { return }
        // A failed fetch bails rather than defaulting to "nothing survives" —
        // an empty survivor set would retire every asset named, which is the
        // one direction this must never guess in.
        guard let visible = try? context.fetch(
            FetchDescriptor<Memory>(predicate: Memory.visible)) else { return }
        let orphaned = Set(assets).subtracting(visible.flatMap(\.photoIDs))
        guard !orphaned.isEmpty else { return }

        guard let rows = try? context.fetch(FetchDescriptor<Photo>()) else { return }
        var retired = false
        for row in rows where orphaned.contains(row.assetID) && row.deletedAt == nil {
            row.deletedAt = .now
            row.updatedAt = .now
            retired = true
        }
        if retired { try? context.save() }
    }

    /// Newest first. `sortDate` falls back to when a picture arrived, because
    /// nothing that predates this record has a capture date to sort by.
    static func all(in context: ModelContext) -> [Photo] {
        let photos = (try? context.fetch(
            FetchDescriptor<Photo>(predicate: Photo.visible))) ?? []
        return photos.sorted { $0.sortDate > $1.sortDate }
    }
}
