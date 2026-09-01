import Foundation
import SwiftData

/// A named collection. Made by one of you, added to by both.
@Model
final class Album {
    var id: UUID = UUID()
    var name: String = ""
    /// Chosen deliberately. When nil the newest member stands in, so a new
    /// album is never a blank square.
    var coverAssetID: String?
    /// The line the couple writes under the cover — not a caption on any one
    /// photo, but what the album itself is about. Defaults empty rather than
    /// absent, so the header always has a place to write one instead of a
    /// hole where the sentiment goes until somebody does.
    var caption: String = ""
    var authorID: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    init(name: String, authorID: String) {
        self.id = UUID()
        self.name = name
        self.authorID = authorID
        self.createdAt = .now
        self.updatedAt = .now
    }

    static var visible: Predicate<Album> {
        #Predicate<Album> { $0.deletedAt == nil }
    }
}

/// One photo's membership of one album.
///
/// A record rather than a field because a photo may be in as many albums as you
/// like. Its id is **derived from the album and the asset**, so the two of you
/// filing one picture into 🎀 from different phones converge on a single row —
/// the property whose absence left co-op matches duplicated for days.
///
/// Removing a photo from an album tombstones this, and touches nothing else:
/// the picture and its other albums are unaffected.
@Model
final class AlbumEntry {
    var id: UUID = UUID()
    var albumID: UUID = UUID()
    var assetID: String = ""
    var authorID: String = ""
    var addedAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    init(albumID: UUID, assetID: String, authorID: String) {
        self.id = AlbumEntry.id(album: albumID, asset: assetID)
        self.albumID = albumID
        self.assetID = assetID
        self.authorID = authorID
        self.addedAt = .now
        self.updatedAt = .now
    }

    static func id(album: UUID, asset: String) -> UUID {
        DerivedUUID.from("entry:\(album.uuidString):\(asset)")
    }

    static var visible: Predicate<AlbumEntry> {
        #Predicate<AlbumEntry> { $0.deletedAt == nil }
    }
}
