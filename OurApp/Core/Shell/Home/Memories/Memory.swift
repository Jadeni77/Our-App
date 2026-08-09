import Foundation
import SwiftData

/// One moment: a few photos, a note, a day.
///
/// The note is what a photo library doesn't give you, and it is why this is not
/// a second Photos.app. §7 hygiene from the first line — stable id, `updatedAt`,
/// `authorID`, tombstone — with no unique constraint and every property
/// defaulted, because SwiftData's CloudKit mirroring rejects both.
@Model
final class Memory {
    /// At most this many photos; the picker enforces it too, but a record that
    /// can grow without bound is a record that eventually does.
    static let maxPhotos = 9

    var id: UUID = UUID()
    /// User data — stored verbatim, never translated. Optional: some moments
    /// are just the picture.
    var note: String = ""
    /// A floating civil day at noon UTC (H8), so two phones agree which day a
    /// memory belongs to.
    var day: Date = Date.now
    /// `Partner.rawValue` — who added it, so a synced timeline merges by author.
    var authorID: String = ""
    /// Ordered filenames in `MemoryPhotoStore`. The first is what the grid shows.
    var photoIDs: [String] = []
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    init(note: String, day: Date, authorID: String, photoIDs: [String]) {
        self.id = UUID()
        self.note = note
        self.day = SpecialDateSchedule.anchor(for: day)
        self.authorID = authorID
        self.photoIDs = Array(photoIDs.prefix(Self.maxPhotos))
        self.updatedAt = .now
    }
}

extension Memory {
    /// The one definition of "not deleted".
    static var visible: Predicate<Memory> {
        #Predicate<Memory> { $0.deletedAt == nil }
    }
}
