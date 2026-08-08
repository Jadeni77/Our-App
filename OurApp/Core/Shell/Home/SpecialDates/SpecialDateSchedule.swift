import Foundation

/// Pure date math for Special Dates — no SwiftUI, no view state, so every rule
/// here is unit-testable (the `DaysTogether` / `CuisinePool` pattern).
///
/// Everything compares **start-of-day in the given calendar**, so counts roll
/// at midnight rather than on 24-hour boundaries — the same rule the day
/// counter on Home follows.
enum SpecialDateSchedule {
    enum Status: Equatable {
        case today
        case upcoming(days: Int)
        case passed(daysAgo: Int)
    }

    /// The next time this date comes around, or nil for a one-off already past.
    /// A date landing today returns today, not next year.
    static func nextOccurrence(of date: Date,
                               repeatsYearly: Bool,
                               from now: Date = .now,
                               calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        let anchor = calendar.startOfDay(for: date)

        guard repeatsYearly else {
            return anchor < today ? nil : anchor
        }
        if anchor >= today { return anchor }

        // Search from the start of yesterday so that a match landing *today*
        // is still "after" the search start and is returned as today.
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return nil }
        let monthDay = calendar.dateComponents([.month, .day], from: anchor)
        // .nextTime rolls an impossible date (Feb 29 in a common year) forward
        // to Mar 1 — the same way iOS itself resolves it.
        return calendar.nextDate(after: yesterday,
                                 matching: monthDay,
                                 matchingPolicy: .nextTime,
                                 direction: .forward)
            .map { calendar.startOfDay(for: $0) }
    }

    static func status(of date: Date,
                       repeatsYearly: Bool,
                       from now: Date = .now,
                       calendar: Calendar = .current) -> Status {
        let today = calendar.startOfDay(for: now)

        guard let next = nextOccurrence(of: date, repeatsYearly: repeatsYearly,
                                        from: now, calendar: calendar) else {
            let anchor = calendar.startOfDay(for: date)
            return .passed(daysAgo: calendar.dateComponents([.day], from: anchor, to: today).day ?? 0)
        }
        let days = calendar.dateComponents([.day], from: today, to: next).day ?? 0
        return days == 0 ? .today : .upcoming(days: days)
    }

    /// Splits dates into the page's two sections: coming up soonest-first
    /// (today first of all), then passed most-recent-first. Tombstoned rows are
    /// dropped. The ordering isn't expressible as a `SortDescriptor`, so it
    /// runs in Swift over the query results.
    @MainActor
    static func ordered(_ dates: [SpecialDate],
                        from now: Date = .now,
                        calendar: Calendar = .current)
        -> (comingUp: [SpecialDate], passed: [SpecialDate]) {
        var comingUp: [(date: SpecialDate, key: Int)] = []
        var passed: [(date: SpecialDate, key: Int)] = []

        for entry in dates where entry.deletedAt == nil {
            switch status(of: entry.date, repeatsYearly: entry.repeatsYearly,
                          from: now, calendar: calendar) {
            case .today:               comingUp.append((entry, 0))
            case .upcoming(let days):  comingUp.append((entry, days))
            case .passed(let daysAgo): passed.append((entry, daysAgo))
            }
        }
        return (comingUp.sorted { $0.key < $1.key }.map(\.date),
                passed.sorted { $0.key < $1.key }.map(\.date))
    }

    /// What Home's tile should show: nil unless the nearest date is today or
    /// at most `nearDays` away. A number that's almost always far off becomes
    /// wallpaper — the tile stays clean until something is actually close.
    @MainActor
    static func badge(for dates: [SpecialDate],
                      nearDays: Int = 7,
                      from now: Date = .now,
                      calendar: Calendar = .current) -> Status? {
        guard let next = ordered(dates, from: now, calendar: calendar).comingUp.first else {
            return nil
        }
        switch status(of: next.date, repeatsYearly: next.repeatsYearly,
                      from: now, calendar: calendar) {
        case .today:
            return .today
        case .upcoming(let days) where days <= nearDays:
            return .upcoming(days: days)
        case .upcoming, .passed:
            return nil
        }
    }
}
