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
    static func seed(in context: ModelContext, authorID: String) {
        guard let memories = try? context.fetch(FetchDescriptor<Memory>()),
              let existing = try? context.fetch(FetchDescriptor<Photo>())
        else { return }

        var known = Set(existing.map(\.assetID))
        var inserted = false
        for memory in memories {
            for asset in memory.photoIDs where !known.contains(asset) {
                known.insert(asset)
                // Credited to whoever wrote the memory it came in, not to
                // whoever happens to be holding the phone during the seed.
                context.insert(Photo(assetID: asset, authorID: memory.authorID))
                inserted = true
            }
        }
        if inserted { try? context.save() }
    }

    /// Newest first. `sortDate` falls back to when a picture arrived, because
    /// nothing that predates this record has a capture date to sort by.
    static func all(in context: ModelContext) -> [Photo] {
        let photos = (try? context.fetch(
            FetchDescriptor<Photo>(predicate: Photo.visible))) ?? []
        return photos.sorted { $0.sortDate > $1.sortDate }
    }
}
