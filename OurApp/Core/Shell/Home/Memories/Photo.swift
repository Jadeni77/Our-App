import Foundation
import SwiftData

/// What we know *about* a picture — never the picture itself.
///
/// The bytes stay in `MemoryPhotoStore`, which already resizes them, already
/// syncs them separately from records, and already knows a photo may arrive
/// after the thing that mentions it. This record adds only what a library
/// needs: who added it, when it was taken, what they called it.
///
/// Its id is derived from the asset id, so a picture noticed by both phones is
/// one row rather than two.
@Model
final class Photo {
    var id: UUID = UUID()
    var assetID: String = ""
    var authorID: String = ""
    /// When the picture was taken, when we know. Nil for everything that
    /// arrived before this record existed, which is why ordering falls back to
    /// `addedAt` rather than pretending.
    var takenAt: Date?
    var addedAt: Date = Date.now
    var caption: String = ""
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    init(assetID: String, authorID: String, takenAt: Date? = nil, caption: String = "") {
        self.id = Photo.id(for: assetID)
        self.assetID = assetID
        self.authorID = authorID
        self.takenAt = takenAt
        self.caption = caption
        self.addedAt = .now
        self.updatedAt = .now
    }

    static func id(for assetID: String) -> UUID { DerivedUUID.from("photo:" + assetID) }

    /// What the library sorts by: the moment it happened if we know it,
    /// otherwise the moment it arrived.
    var sortDate: Date { takenAt ?? addedAt }

    static var visible: Predicate<Photo> {
        #Predicate<Photo> { $0.deletedAt == nil }
    }
}
