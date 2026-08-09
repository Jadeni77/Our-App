#if DEBUG
import Foundation
import SwiftData

/// Headless screenshot verification can't tap (simctl), so `-seedSpecialDates`
/// puts a representative set of dates in the store at launch — one within the
/// badge window, one further out, one recurring, one passed.
///
/// DEBUG only, and it refuses to run when the store already holds dates, so it
/// can never overwrite real ones. Same motivation as `-openSettings` and
/// `-moonshot`: reach a state a screenshot needs without a finger.
enum SpecialDatesDebugSeed {
    static func runIfRequested(in container: ModelContainer) {
        guard ProcessInfo.processInfo.arguments.contains("-seedSpecialDates") else { return }

        let context = ModelContext(container)
        // Counts ordinary dates only. A migrated anniversary is one row that
        // arrives before any seeding, and counting it would make this a silent
        // no-op on exactly the phones that have real history.
        let existing = (try? context.fetchCount(FetchDescriptor<SpecialDate>(
            predicate: #Predicate { !$0.isAnniversary }))) ?? 0
        guard existing == 0 else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        // Through `anchor`, like the editor — a raw local instant would be read
        // back as the wrong civil day (see SpecialDateSchedule's anchor note).
        func offset(_ days: Int) -> Date {
            SpecialDateSchedule.anchor(
                for: calendar.date(byAdding: .day, value: days, to: today) ?? today,
                calendar: calendar)
        }

        // An anniversary too, unless one already exists — the card's set state
        // is otherwise unreachable without tapping, and simctl can't tap.
        let anniversaries = (try? context.fetchCount(FetchDescriptor<SpecialDate>(
            predicate: SpecialDate.anniversary))) ?? 0
        if anniversaries == 0 {
            context.insert(SpecialDate(title: "", date: offset(-1165),
                                       repeatsYearly: true, isAnniversary: true))
        }

        context.insert(SpecialDate(title: "Her birthday", emoji: "🎂",
                                   date: offset(3), repeatsYearly: true))
        context.insert(SpecialDate(title: "Kyoto trip", emoji: "✈️",
                                   date: offset(26)))
        context.insert(SpecialDate(title: "Moved in together", emoji: "🏠",
                                   date: offset(88), repeatsYearly: true))
        context.insert(SpecialDate(title: "First date", emoji: "🎡",
                                   date: offset(-1165)))
        try? context.save()
    }
}
#endif
