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

    /// A date paired with the status computed for it, so callers never have to
    /// work it out a second time.
    typealias Entry = (date: SpecialDate, status: Status)

    /// A special date is a **floating civil day** — "Aug 14" is Aug 14 wherever
    /// we are, not an instant that happens to fall on it. SwiftData stores an
    /// absolute `Date`, so the convention is: the stored value is **noon UTC of
    /// that civil day**, and every reader converts it back through `localDay`.
    ///
    /// Interpreting the raw instant in the device's calendar is what goes
    /// wrong: a birthday added at 07:00 in Shanghai is 23:00 the previous day
    /// in UTC and reads a day early after flying to New York. Pinning it at
    /// *local* noon isn't enough either — real offsets span UTC−12…UTC+14, 26
    /// hours, so no single instant reads as the same day everywhere. Storing
    /// the civil day and rebuilding it locally does, and it keeps two phones in
    /// different timezones agreeing about one record when sync lands.
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// Picked day → stored anchor. Takes the civil day the user chose in their
    /// own calendar and pins it at noon UTC.
    static func anchor(for picked: Date, calendar: Calendar = .current) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day], from: picked)
        return utc.date(from: DateComponents(year: parts.year, month: parts.month,
                                             day: parts.day, hour: 12)) ?? picked
    }

    /// Stored anchor → the same civil day at midnight in the reader's calendar.
    /// Everything that interprets or displays a stored date goes through here.
    static func localDay(of stored: Date, calendar: Calendar = .current) -> Date {
        let parts = utc.dateComponents([.year, .month, .day], from: stored)
        return calendar.date(from: DateComponents(year: parts.year, month: parts.month,
                                                  day: parts.day))
            ?? calendar.startOfDay(for: stored)
    }

    /// The next time this date comes around, or nil for a one-off already past.
    /// A date landing today returns today, not next year.
    static func nextOccurrence(of date: Date,
                               repeatsYearly: Bool,
                               from now: Date = .now,
                               calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        let anchor = localDay(of: date, calendar: calendar)

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
            let anchor = localDay(of: date, calendar: calendar)
            return .passed(daysAgo: calendar.dateComponents([.day], from: anchor, to: today).day ?? 0)
        }
        let days = calendar.dateComponents([.day], from: today, to: next).day ?? 0
        return days == 0 ? .today : .upcoming(days: days)
    }

    /// Splits dates into the page's two sections: coming up soonest-first
    /// (today first of all), then passed most-recent-first. Tombstoned rows are
    /// dropped. The ordering isn't expressible as a `SortDescriptor`, so it
    /// runs in Swift over the query results.
    ///
    /// Each date is returned **with** the status computed for it. Handing back
    /// bare dates would make every row derive its own — doubling the calendar
    /// work, and letting a render that straddles midnight sort by one day's
    /// answer while displaying the next day's.
    @MainActor
    static func ordered(_ dates: [SpecialDate],
                        from now: Date = .now,
                        calendar: Calendar = .current)
        -> (anniversary: Entry?, comingUp: [Entry], passed: [Entry]) {
        var flagged: [SpecialDate] = []
        var rest: [SpecialDate] = []

        for date in dates where date.deletedAt == nil {
            if date.isAnniversary { flagged.append(date) } else { rest.append(date) }
        }

        // Exactly one anniversary is supposed to exist (P17). If more ever do,
        // the earliest wins and the others render as normal dates — a defined
        // outcome, and one that can't hide the stray row.
        let sortedFlagged = flagged.sorted { $0.date < $1.date }
        rest.append(contentsOf: sortedFlagged.dropFirst())

        func entry(for date: SpecialDate) -> Entry {
            (date, status(of: date.date, repeatsYearly: date.repeatsYearly,
                          from: now, calendar: calendar))
        }

        var comingUp: [Entry] = []
        var passed: [Entry] = []
        for date in rest {
            let made = entry(for: date)
            if case .passed = made.status { passed.append(made) } else { comingUp.append(made) }
        }

        return (anniversary: sortedFlagged.first.map(entry),
                comingUp: comingUp.sorted(by: nearestFirst),
                passed: passed.sorted(by: nearestFirst))
    }

    /// Ties break on title so two dates on the same day can't swap places
    /// between launches — `Array.sorted` guarantees no stability, and the query
    /// feeding it guarantees no order.
    private static func nearestFirst(_ lhs: Entry, _ rhs: Entry) -> Bool {
        let left = distance(of: lhs.status), right = distance(of: rhs.status)
        return left == right ? lhs.date.title < rhs.date.title : left < right
    }

    private static func distance(of status: Status) -> Int {
        switch status {
        case .today: 0
        case .upcoming(let days): days
        case .passed(let daysAgo): daysAgo
        }
    }

    /// What Home's tile should show: nil unless the nearest date is today or
    /// at most `nearDays` away. A number that's almost always far off becomes
    /// wallpaper — the tile stays clean until something is actually close.
    @MainActor
    static func badge(for dates: [SpecialDate],
                      nearDays: Int = 7,
                      from now: Date = .now,
                      calendar: Calendar = .current) -> Status? {
        let split = ordered(dates, from: now, calendar: calendar)
        // The anniversary has its own card on the page, but it is exactly the
        // date we most want warning about — so the tile weighs it against the
        // others rather than ignoring it.
        let candidates = ([split.anniversary].compactMap { $0 } + split.comingUp)
            .sorted(by: nearestFirst)

        guard let next = candidates.first else { return nil }
        switch next.status {
        case .today:
            return .today
        case .upcoming(let days) where days <= nearDays:
            return .upcoming(days: days)
        case .upcoming, .passed:
            return nil
        }
    }
}
