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

        // Rows that predate the seed learning to carry a date. Once each, and
        // only ever nil → a date, so this is not a write that repeats on every
        // launch; both phones derive the same day from the same memory, so it
        // converges rather than ping-ponging. Tombstoned rows are left alone:
        // nothing is going to sort them.
        for row in existing where row.takenAt == nil && row.deletedAt == nil {
            guard let day = takenAt[row.assetID] else { continue }
            row.takenAt = day
            row.updatedAt = .now
            changed = true
        }

        if changed { try? context.save() }
    }

    /// Newest first. `sortDate` falls back to when a picture arrived, because
    /// nothing that predates this record has a capture date to sort by.
    static func all(in context: ModelContext) -> [Photo] {
        let photos = (try? context.fetch(
            FetchDescriptor<Photo>(predicate: Photo.visible))) ?? []
        return photos.sorted { $0.sortDate > $1.sortDate }
    }
}
