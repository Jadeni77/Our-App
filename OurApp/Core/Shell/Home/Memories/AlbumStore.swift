import Foundation
import SwiftData

/// Albums, and what is in them. No SwiftUI in here on purpose — membership,
/// counts and covers are the rules the feature turns on, and rules are worth
/// testing without a simulator.
///
/// Every count and every cover is **derived** from live `AlbumEntry` rows,
/// never stored as a field on `Album`. A stored count is a number that drifts
/// out of step with the rows it claims to describe, and this project has had
/// to remove every running total it ever kept.
@MainActor
enum AlbumStore {
    /// Newest first, matching every other list in this feature.
    static func albums(in context: ModelContext) -> [Album] {
        let all = (try? context.fetch(
            FetchDescriptor<Album>(predicate: Album.visible))) ?? []
        return all.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    static func create(name: String, authorID: String, in context: ModelContext) -> Album {
        let album = Album(name: name, authorID: authorID)
        context.insert(album)
        try? context.save()
        return album
    }

    static func rename(_ album: Album, to name: String, in context: ModelContext) {
        album.name = name
        album.updatedAt = .now
        try? context.save()
    }

    /// Setting the cover to an asset that isn't (or is no longer) a member is
    /// allowed to happen here without complaint — `cover(of:)` is where the
    /// choice is checked, and it falls back rather than trusting a stale id.
    static func setCover(_ album: Album, to assetID: String?, in context: ModelContext) {
        album.coverAssetID = assetID
        album.updatedAt = .now
        try? context.save()
    }

    /// Tombstones the album and nothing else. Deleting an album is deleting a
    /// *label* — its memberships and the photos behind them are untouched, so
    /// nothing the two of you filed is ever lost by un-filing it.
    static func delete(_ album: Album, in context: ModelContext) {
        album.deletedAt = .now
        album.updatedAt = .now
        try? context.save()
    }

    /// Filing an already-filed photo revives its membership rather than adding
    /// a second row — the id is derived from the album and the asset, so
    /// there is only ever one row to find, whichever phone or however many
    /// times either of you taps "add".
    ///
    /// The revival is only half the feature: it replicates because
    /// `SyncApply.applyAlbumEntry` is the one type exempted from the
    /// sticky-tombstone rule. Without that exemption this line is a local-only
    /// resurrection the other phone refuses forever, which is exactly what
    /// shipped for one review round.
    static func add(assetID: String, to album: Album, authorID: String,
                    in context: ModelContext) {
        let id = AlbumEntry.id(album: album.id, asset: assetID)
        if let existing = try? context.fetch(
            FetchDescriptor<AlbumEntry>(predicate: #Predicate { $0.id == id })).first {
            // Already an active member: adding it again is a no-op, not a
            // second write racing the first.
            guard existing.deletedAt != nil else { return }
            existing.deletedAt = nil
            existing.updatedAt = .now
        } else {
            context.insert(AlbumEntry(albumID: album.id, assetID: assetID,
                                      authorID: authorID))
        }
        try? context.save()
    }

    /// Taking a photo out of an album tombstones its membership row alone.
    /// The `Photo` and every other album it belongs to are untouched — the
    /// property that keeps filing from feeling dangerous.
    static func remove(assetID: String, from album: Album, in context: ModelContext) {
        let id = AlbumEntry.id(album: album.id, asset: assetID)
        guard let entry = try? context.fetch(
            FetchDescriptor<AlbumEntry>(predicate: #Predicate { $0.id == id })).first
        else { return }
        entry.deletedAt = .now
        entry.updatedAt = .now
        try? context.save()
    }

    /// The album's photos, newest-added first — the same ordering `cover(of:)`
    /// relies on to find the newest member.
    static func assets(of album: Album, in context: ModelContext) -> [String] {
        entries(of: album, in: context)
            .sorted { $0.addedAt > $1.addedAt }
            .map(\.assetID)
    }

    /// **Both delegate to `summary(of:)`**, which is what the app actually
    /// calls. They used to re-implement the same two rules a few lines apart,
    /// so the shipped cover rule had no test and the tested one had no caller —
    /// three tests exercising code the app never ran, which is worse than no
    /// tests because it reads like coverage.
    static func count(of album: Album, in context: ModelContext) -> Int {
        summary(of: album, in: context).count
    }

    /// The chosen cover if it's still a member, otherwise the newest member,
    /// otherwise nothing at all. An empty album has to say it's empty rather
    /// than invent a picture nobody put there.
    static func cover(of album: Album, in context: ModelContext) -> String? {
        summary(of: album, in: context).cover
    }

    /// The cover and the count together, off **one** fetch of the live
    /// memberships instead of the two they would each run alone — a grid asking
    /// for both per tile, once per render, is exactly the case that turns a
    /// single extra fetch into a noticeable number of them.
    ///
    /// This is where the cover rule lives, and the only place it lives:
    /// the chosen cover while it is still a member, otherwise the newest
    /// member, otherwise nothing.
    static func summary(of album: Album, in context: ModelContext) -> (cover: String?, count: Int) {
        let members = entries(of: album, in: context)
        let cover: String?
        if let chosen = album.coverAssetID,
           members.contains(where: { $0.assetID == chosen }) {
            cover = chosen
        } else {
            cover = members.sorted { $0.addedAt > $1.addedAt }.first?.assetID
        }
        return (cover, members.count)
    }

    /// Live memberships only. A tombstoned entry stopped counting the moment
    /// it was removed, which is the whole point of deriving rather than
    /// storing (`countsAreDerivedNotStored`).
    ///
    /// A membership is also dropped when the **photo behind it** has been
    /// retired — deleting a memory takes its files with it, so a row pointing
    /// at one is a tile that can never load. This was unreachable until
    /// `PhotoLibrary.retire` existed; now it is the difference between an album
    /// that quietly shrinks and one that counts squares nobody can see.
    ///
    /// **A membership with no `Photo` row at all is kept.** That is the
    /// legitimate "the membership arrived before the photo did" case — records
    /// travel independently of each other and of the bytes — and treating an
    /// absent row as a retired one would hide every photo mid-sync.
    private static func entries(of album: Album, in context: ModelContext) -> [AlbumEntry] {
        let albumID = album.id
        let members = (try? context.fetch(FetchDescriptor<AlbumEntry>(
            predicate: #Predicate { $0.albumID == albumID && $0.deletedAt == nil }))) ?? []
        guard !members.isEmpty else { return [] }
        let retired = retiredAssets(in: context)
        guard !retired.isEmpty else { return members }
        return members.filter { !retired.contains($0.assetID) }
    }

    /// Assets whose `Photo` has been tombstoned. Fetched by predicate rather
    /// than by filtering the whole library, so on the normal path — nobody has
    /// deleted a memory — this reads no rows at all.
    private static func retiredAssets(in context: ModelContext) -> Set<String> {
        let rows = (try? context.fetch(FetchDescriptor<Photo>(
            predicate: #Predicate { $0.deletedAt != nil }))) ?? []
        return Set(rows.map(\.assetID))
    }
}
