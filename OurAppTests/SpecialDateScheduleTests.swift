import Foundation
import Testing
@testable import OurApp

struct SpecialDateScheduleTests {
    /// A fixed UTC gregorian calendar so these tests can't drift with the
    /// machine's locale or timezone.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: One-off dates

    @Test func oneOffInTheFutureCountsDown() {
        let status = SpecialDateSchedule.status(of: day(2026, 9, 2),
                                                repeatsYearly: false,
                                                from: day(2026, 8, 7),
                                                calendar: calendar)
        #expect(status == .upcoming(days: 26))
    }

    @Test func oneOffTodayIsToday() {
        let status = SpecialDateSchedule.status(of: day(2026, 8, 7),
                                                repeatsYearly: false,
                                                from: day(2026, 8, 7),
                                                calendar: calendar)
        #expect(status == .today)
    }

    @Test func oneOffInThePastCountsUp() {
        let status = SpecialDateSchedule.status(of: day(2023, 5, 21),
                                                repeatsYearly: false,
                                                from: day(2026, 8, 7),
                                                calendar: calendar)
        #expect(status == .passed(daysAgo: 1174))
    }

    @Test func oneOffInThePastHasNoNextOccurrence() {
        #expect(SpecialDateSchedule.nextOccurrence(of: day(2023, 5, 21),
                                                   repeatsYearly: false,
                                                   from: day(2026, 8, 7),
                                                   calendar: calendar) == nil)
    }

    // MARK: Yearly dates

    @Test func yearlyBeforeItsDayCountsDownWithinTheSameYear() {
        let status = SpecialDateSchedule.status(of: day(2000, 8, 14),
                                                repeatsYearly: true,
                                                from: day(2026, 8, 7),
                                                calendar: calendar)
        #expect(status == .upcoming(days: 7))
    }

    @Test func yearlyOnItsDayIsToday() {
        let status = SpecialDateSchedule.status(of: day(2000, 8, 14),
                                                repeatsYearly: true,
                                                from: day(2026, 8, 14),
                                                calendar: calendar)
        #expect(status == .today)
    }

    @Test func yearlyAfterItsDayRollsToNextYear() {
        let next = SpecialDateSchedule.nextOccurrence(of: day(2000, 8, 14),
                                                      repeatsYearly: true,
                                                      from: day(2026, 8, 15),
                                                      calendar: calendar)
        #expect(next == day(2027, 8, 14))
    }

    @Test func yearlyNeverReportsPassed() {
        // Whatever day we ask on, a recurring date always has a next occurrence.
        for offset in [-400, -1, 0, 1, 400] {
            let now = calendar.date(byAdding: .day, value: offset, to: day(2026, 8, 14))!
            let status = SpecialDateSchedule.status(of: day(2000, 8, 14),
                                                    repeatsYearly: true,
                                                    from: now,
                                                    calendar: calendar)
            if case .passed = status {
                Issue.record("recurring date reported passed at offset \(offset)")
            }
        }
    }

    @Test func february29ResolvesToMarchFirstInACommonYear() {
        // 2027 is not a leap year: the anniversary lands on Mar 1, the way iOS
        // itself rolls an impossible date forward.
        let next = SpecialDateSchedule.nextOccurrence(of: day(2024, 2, 29),
                                                      repeatsYearly: true,
                                                      from: day(2027, 1, 1),
                                                      calendar: calendar)
        #expect(next == day(2027, 3, 1))
    }

    @Test func february29StaysOnFebruary29InALeapYear() {
        let next = SpecialDateSchedule.nextOccurrence(of: day(2024, 2, 29),
                                                      repeatsYearly: true,
                                                      from: day(2028, 1, 1),
                                                      calendar: calendar)
        #expect(next == day(2028, 2, 29))
    }

    // MARK: Ordering

    @MainActor
    @Test func orderedPutsTodayFirstThenSoonest_andPassedMostRecentFirst() {
        let today = SpecialDate(title: "Today", date: day(2026, 8, 7))
        let soon = SpecialDate(title: "Soon", date: day(2026, 8, 14))
        let later = SpecialDate(title: "Later", date: day(2026, 11, 3))
        let recentlyPassed = SpecialDate(title: "Recent", date: day(2026, 7, 1))
        let longPassed = SpecialDate(title: "Old", date: day(2023, 5, 21))

        let split = SpecialDateSchedule.ordered(
            [later, longPassed, today, recentlyPassed, soon],
            from: day(2026, 8, 7), calendar: calendar)

        #expect(split.comingUp.map(\.title) == ["Today", "Soon", "Later"])
        #expect(split.passed.map(\.title) == ["Recent", "Old"])
    }

    @MainActor
    @Test func orderedSkipsTombstonedRows() {
        let live = SpecialDate(title: "Live", date: day(2026, 8, 14))
        let deleted = SpecialDate(title: "Deleted", date: day(2026, 8, 10))
        deleted.deletedAt = .now

        let split = SpecialDateSchedule.ordered([live, deleted],
                                                from: day(2026, 8, 7),
                                                calendar: calendar)

        #expect(split.comingUp.map(\.title) == ["Live"])
        #expect(split.passed.isEmpty)
    }

    // MARK: Home tile badge

    @MainActor
    @Test func badgeShowsWhenTheNextDateIsWithinAWeek() {
        let soon = SpecialDate(title: "Soon", date: day(2026, 8, 14))
        #expect(SpecialDateSchedule.badge(for: [soon],
                                          from: day(2026, 8, 7),
                                          calendar: calendar) == .upcoming(days: 7))
    }

    @MainActor
    @Test func badgeShowsTodayOnTheDay() {
        let now = SpecialDate(title: "Now", date: day(2026, 8, 7))
        #expect(SpecialDateSchedule.badge(for: [now],
                                          from: day(2026, 8, 7),
                                          calendar: calendar) == .today)
    }

    @MainActor
    @Test func badgeIsSilentBeyondAWeek() {
        let far = SpecialDate(title: "Far", date: day(2026, 8, 15))
        #expect(SpecialDateSchedule.badge(for: [far],
                                          from: day(2026, 8, 7),
                                          calendar: calendar) == nil)
    }

    @MainActor
    @Test func badgeIgnoresPassedAndTombstonedDates() {
        let passed = SpecialDate(title: "Passed", date: day(2026, 8, 1))
        let deleted = SpecialDate(title: "Deleted", date: day(2026, 8, 8))
        deleted.deletedAt = .now
        #expect(SpecialDateSchedule.badge(for: [passed, deleted],
                                          from: day(2026, 8, 7),
                                          calendar: calendar) == nil)
    }
}
