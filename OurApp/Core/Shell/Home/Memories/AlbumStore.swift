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

    static func count(of album: Album, in context: ModelContext) -> Int {
        entries(of: album, in: context).count
    }

    /// The chosen cover if it's still a member, otherwise the newest member,
    /// otherwise nothing at all. An empty album has to say it's empty rather
    /// than invent a picture nobody put there.
    static func cover(of album: Album, in context: ModelContext) -> String? {
        let members = entries(of: album, in: context)
        if let chosen = album.coverAssetID,
           members.contains(where: { $0.assetID == chosen }) {
            return chosen
        }
        return members.sorted { $0.addedAt > $1.addedAt }.first?.assetID
    }

    /// `cover(of:)` and `count(of:)` together, off one fetch of the live
    /// memberships instead of the two each would run alone — a grid asking
    /// for both per tile, once per render, is exactly the case that turns a
    /// single extra fetch into a noticeable number of them.
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
    private static func entries(of album: Album, in context: ModelContext) -> [AlbumEntry] {
        let albumID = album.id
        return (try? context.fetch(FetchDescriptor<AlbumEntry>(
            predicate: #Predicate { $0.albumID == albumID && $0.deletedAt == nil }))) ?? []
    }
}
