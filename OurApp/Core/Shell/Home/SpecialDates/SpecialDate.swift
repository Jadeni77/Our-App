import Foundation
import SwiftData

/// One date we don't want to miss — the first hub sub-page's record (P16).
///
/// Local-only today, but it carries DESIGN.md §7's record hygiene from the
/// first line (stable id, updatedAt, authorID, soft-delete tombstone) so the
/// CloudKit move is mechanical rather than a migration.
///
/// Two shape rules exist for that future: **no `@Attribute(.unique)`** and
/// **every stored property optional or defaulted** — SwiftData's CloudKit
/// mirroring rejects both unique constraints and non-defaulted properties.
@Model
final class SpecialDate {
    var id: UUID = UUID()
    /// User data — stored verbatim, never translated.
    var title: String = ""
    var emoji: String = "🎂"
    /// The anchor day. For a yearly date only its month/day matter after the
    /// first occurrence; the year records when it started.
    var date: Date = Date.now
    var repeatsYearly: Bool = false
    var updatedAt: Date = Date.now
    /// Nil until pairing exists — there is only one author on one phone today.
    var authorID: String?
    /// Soft-delete tombstone. Set on delete; the row is never removed.
    var deletedAt: Date?

    init(title: String, emoji: String = "🎂", date: Date, repeatsYearly: Bool = false) {
        self.id = UUID()
        self.title = title
        self.emoji = emoji
        self.date = date
        self.repeatsYearly = repeatsYearly
        self.updatedAt = .now
    }
}

extension SpecialDate {
    /// The one definition of "not deleted". Every query that shows dates to a
    /// human filters on this — spelling it out per call site is how the
    /// tombstone rule eventually gets missed in one of them.
    static var visible: Predicate<SpecialDate> {
        #Predicate<SpecialDate> { $0.deletedAt == nil }
    }
}
