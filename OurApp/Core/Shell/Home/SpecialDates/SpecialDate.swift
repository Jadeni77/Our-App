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
    /// **Retired.** Superseded by `iconID`; kept only so `DateIconMigration`
    /// can read it, because dropping the column in the same change that
    /// consumes it would destroy every existing pick. Removed in a later slice
    /// once the migration has run on both phones. Nothing reads it in the UI.
    var emoji: String = "🎂"
    /// The drawn icon's stable id. `""` means "not migrated yet" — deliberately
    /// distinct from `heart`, so migrating can't be confused with choosing.
    var iconID: String = ""
    /// The anchor day. For a yearly date only its month/day matter after the
    /// first occurrence; the year records when it started.
    var date: Date = Date.now
    var repeatsYearly: Bool = false
    /// The one date Home's counter reads (P17). Exactly one record carries it.
    var isAnniversary: Bool = false
    var updatedAt: Date = Date.now
    /// Nil until pairing exists — there is only one author on one phone today.
    var authorID: String?
    /// Soft-delete tombstone. Set on delete; the row is never removed.
    var deletedAt: Date?

    /// `authorID` defaults to this install (P18) rather than staying nil.
    ///
    /// Nothing on any write path used to set it, so every date shipped with a
    /// nil author — and `SyncEnvelope.supersedes` breaks its tie on `authorID`,
    /// which means `"" > ""` in both directions. Two phones editing one date at
    /// the same instant would each reject the other and disagree forever, with
    /// no conflict either could see. Exactly the failure the tiebreak exists to
    /// prevent, on the one shared type where two people genuinely edit one row.
    init(title: String, emoji: String = "🎂", date: Date,
         repeatsYearly: Bool = false, isAnniversary: Bool = false,
         icon: DateIcon? = nil, authorID: String = LocalAuthor.id()) {
        self.authorID = authorID
        self.id = UUID()
        self.title = title
        self.emoji = emoji
        self.date = date
        self.repeatsYearly = repeatsYearly
        self.isAnniversary = isAnniversary
        self.iconID = icon?.rawValue ?? ""
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

    /// Always resolves — an unmigrated or unrecognised id reads as `.heart`.
    var icon: DateIcon {
        get { DateIcon.resolve(iconID) }
        set { iconID = newValue.rawValue }
    }

    /// Home's single-row lookup.
    static var anniversary: Predicate<SpecialDate> {
        #Predicate<SpecialDate> { $0.isAnniversary && $0.deletedAt == nil }
    }
}
