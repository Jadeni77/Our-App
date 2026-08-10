import Foundation
import SwiftData

/// One day you showed up. The 火花 counts these.
///
/// §7 hygiene from the first line — stable id, `updatedAt`, `authorID`,
/// tombstone — with no unique constraint and every property defaulted, because
/// SwiftData's CloudKit mirroring rejects both. That matters more here than
/// usual: a real 火花 is mutual, and this record is shaped so the partner's days
/// merge in with **no migration** when sync lands. Until then it counts one
/// person's days (P19).
@Model
final class CheckIn {
    var id: UUID = UUID()
    /// A floating civil day at noon UTC (H8), so a check-in belongs to the same
    /// day on both phones regardless of where either of you is standing.
    var day: Date = Date.now
    /// This install's id (P18) — never a chosen half of the couple.
    var authorID: String = ""
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    init(day: Date, authorID: String) {
        self.id = UUID()
        self.day = SpecialDateSchedule.anchor(for: day)
        self.authorID = authorID
        self.updatedAt = .now
    }
}

extension CheckIn {
    /// The one definition of "not deleted".
    static var visible: Predicate<CheckIn> {
        #Predicate<CheckIn> { $0.deletedAt == nil }
    }
}
