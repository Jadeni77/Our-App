import Foundation
import OSLog
import SwiftData

/// Legacy rows carry `Partner.rawValue` — "one" or "two" — or nothing at all,
/// from when the owner told the app which half of the couple this phone was.
/// Every one of those rows was written *on this phone*, because nothing has
/// ever synced, so all of them become this install's id (P18).
///
/// **Idempotent by construction**, not by a flag: it matches the old values
/// rather than latching "did I run" in defaults. The anniversary migration used
/// a latch, and the latch going stale against a writer that still wrote the old
/// key is precisely how it deleted the anniversary on every launch (H14). A
/// migration that recognises its own output can be run any number of times.
enum AuthorIDMigration {
    /// Values that mean "written before this phone had an id of its own".
    private static var legacy: Set<String> {
        [Partner.one.rawValue, Partner.two.rawValue, ""]
    }

    static func runIfNeeded(in container: ModelContainer,
                            authorID: String = LocalAuthor.id()) {
        let context = ModelContext(container)
        var changed = false

        // Fetched whole and filtered in Swift rather than by `#Predicate`:
        // SwiftData can't translate `Set.contains`, and the one time a
        // migration predicate silently matched nothing it did nothing at all
        // (H15). These tables hold tens of rows.
        if let answers = try? context.fetch(FetchDescriptor<QuestionAnswer>()) {
            for row in answers where legacy.contains(row.authorID) {
                row.authorID = authorID
                changed = true
            }
        }
        if let memories = try? context.fetch(FetchDescriptor<Memory>()) {
            for row in memories where legacy.contains(row.authorID) {
                row.authorID = authorID
                changed = true
            }
        }
        if let dates = try? context.fetch(FetchDescriptor<SpecialDate>()) {
            for row in dates where legacy.contains(row.authorID ?? "") {
                row.authorID = authorID
                changed = true
            }
        }

        // Moonshot progress keyed itself off `"couple.devicePartner"`, a
        // defaults key nothing ever wrote — so every phone's rows say `"one"`.
        // They belong to whoever is holding this phone, exactly as the couples
        // records did, and for the same reason: nothing has ever synced.
        if let results = try? context.fetch(FetchDescriptor<MoonshotLevelResult>()) {
            for row in results where legacy.contains(row.partnerID) {
                row.partnerID = authorID
                changed = true
            }
        }
        if let dust = try? context.fetch(FetchDescriptor<MoonshotMoondustEntry>()) {
            for row in dust where legacy.contains(row.partnerID) {
                row.partnerID = authorID
                changed = true
            }
        }
        if let seen = try? context.fetch(FetchDescriptor<MoonshotCoachSeen>()) {
            for row in seen where legacy.contains(row.partnerID) {
                row.partnerID = authorID
                changed = true
            }
        }
        if let cosmetics = try? context.fetch(FetchDescriptor<MoonshotCosmeticSetting>()) {
            for row in cosmetics where legacy.contains(row.partnerID) {
                row.partnerID = authorID
                changed = true
            }
        }

        guard changed else { return }
        do {
            // `updatedAt` is deliberately not bumped: nothing about the moment
            // changed, only how the app spells its author.
            try context.save()
        } catch {
            // Nothing is lost — the rows keep their old ids and the next launch
            // tries again. Logged rather than trapped: an `assertionFailure`
            // here makes DEBUG builds unlaunchable, which is what made the
            // anniversary migration untestable in the first place (H14).
            Logger(subsystem: "OurApp", category: "migration")
                .error("author id migration failed: \(error.localizedDescription)")
        }
    }
}
