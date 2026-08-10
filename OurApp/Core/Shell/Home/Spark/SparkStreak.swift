import Foundation

/// How many days in a row you have shown up.
///
/// Pure, and separate from any view, because the rule below is the one thing in
/// this feature that is easy to get quietly wrong.
enum SparkStreak {
    struct Status: Equatable {
        var current: Int
        var longest: Int
        var checkedInToday: Bool
        /// Alive, but today is not done yet. What the reminder keys off, and
        /// what makes the pill look different at a glance.
        var atRisk: Bool

        static let none = Status(current: 0, longest: 0,
                                 checkedInToday: false, atRisk: false)
    }

    /// **The rule that matters:** a streak that includes yesterday but not yet
    /// today is *alive and at risk*, not broken. The day is not over.
    ///
    /// Counting only runs that end today would collapse the number to 0 at
    /// every midnight and spring it back the moment you tap — which reads as
    /// data loss, not as a rule. This codebase has already shipped one bug of
    /// exactly this shape, when a reference-date origin re-localized west of
    /// UTC and made question selection timezone-dependent; it was invisible
    /// because every test ran in UTC. Hence the `calendar` parameter, and hence
    /// the tests that sweep timezones.
    static func status(for days: [Date],
                       on today: Date = .now,
                       calendar: Calendar = .current) -> Status {
        // `calendar:` must be threaded through — `localDay` defaults to
        // `.current`, and letting it default here while the rest of the
        // function used the passed calendar shifted every streak by a day.
        // It already returns midnight in that calendar, so no `startOfDay`.
        let civil = Set(days.map { SpecialDateSchedule.localDay(of: $0, calendar: calendar) })
        guard !civil.isEmpty else { return .none }

        let todayCivil = calendar.startOfDay(for: today)
        let checkedInToday = civil.contains(todayCivil)

        // Count back from today if today is done, otherwise from yesterday —
        // that is the whole "at risk" idea. If neither is present the run has
        // already ended and the current streak is zero.
        var anchor: Date?
        if checkedInToday {
            anchor = todayCivil
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: todayCivil),
                  civil.contains(yesterday) {
            anchor = yesterday
        }

        var current = 0
        var cursor = anchor
        while let day = cursor, civil.contains(day) {
            current += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: day)
        }

        return Status(current: current,
                      longest: max(longestRun(in: civil, calendar: calendar), current),
                      checkedInToday: checkedInToday,
                      atRisk: current > 0 && !checkedInToday)
    }

    /// The longest run anywhere in the history — kept so a missed day doesn't
    /// erase what a good month was worth.
    private static func longestRun(in civil: Set<Date>, calendar: Calendar) -> Int {
        var longest = 0
        for day in civil {
            // Only start counting from the beginning of a run, so each run is
            // walked once rather than once per day it contains.
            let previous = calendar.date(byAdding: .day, value: -1, to: day)
            if let previous, civil.contains(previous) { continue }

            var length = 0
            var cursor: Date? = day
            while let current = cursor, civil.contains(current) {
                length += 1
                cursor = calendar.date(byAdding: .day, value: 1, to: current)
            }
            longest = max(longest, length)
        }
        return longest
    }
}
