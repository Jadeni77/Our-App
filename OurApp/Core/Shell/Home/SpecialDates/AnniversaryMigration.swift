import Foundation
import OSLog
import SwiftData

/// One-time move of the anniversary out of `UserDefaults` and into a flagged
/// `SpecialDate` (P17). Runs at launch, before any UI reads the store.
///
/// `UserDefaults` does not sync and SwiftData will; the anniversary is the one
/// value both phones must agree on, so it moves first.
enum AnniversaryMigration {
    /// The key couple identity wrote before P17. Owned here now: after this
    /// runs, nothing in the app reads or writes it again.
    static let legacyKey = "couple.anniversary"

    private static let log = Logger(subsystem: "com.jadeni77.OurApp", category: "migration")

    /// `save` is injectable for one reason: the whole no-loss argument rests on
    /// the legacy key surviving a failed save, and that is otherwise only true
    /// by construction, with no test able to prove it.
    static func runIfNeeded(in container: ModelContainer,
                            defaults: UserDefaults = .standard,
                            save: (ModelContext) throws -> Void = { try $0.save() }) {
        guard defaults.object(forKey: legacyKey) != nil else { return }

        let context = ModelContext(container)
        // Falling back to 0 on a failed count risks a second row, which
        // `ordered` resolves deterministically. The other fallback would drop
        // the key without writing anything, which loses the date outright.
        let existing = (try? context.fetchCount(
            FetchDescriptor<SpecialDate>(predicate: SpecialDate.anniversary))) ?? 0
        guard existing == 0 else {
            // Already migrated on an earlier launch — drop the stale key.
            defaults.removeObject(forKey: legacyKey)
            return
        }

        let stored = Date(timeIntervalSinceReferenceDate: defaults.double(forKey: legacyKey))
        context.insert(SpecialDate(title: "",
                                   date: SpecialDateSchedule.anchor(for: stored),
                                   repeatsYearly: true,
                                   isAnniversary: true))
        do {
            try save(context)
            // Only after the row is safely on disk. If the save throws, the key
            // stays and the next launch retries — migrating twice is recoverable,
            // losing the date is not.
            defaults.removeObject(forKey: legacyKey)
        } catch {
            // Logged, not asserted. `assertionFailure` traps in DEBUG, which
            // would turn a store problem into an app that cannot launch at all
            // — a dead end, which principle 7 rules out. The key is still in
            // place, so the next launch retries; this line is how we find out.
            log.error("anniversary migration failed to save: \(error, privacy: .public)")
        }
    }
}
