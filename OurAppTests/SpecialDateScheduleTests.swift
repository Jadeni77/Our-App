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

        #expect(split.comingUp.map(\.date.title) == ["Today", "Soon", "Later"])
        #expect(split.passed.map(\.date.title) == ["Recent", "Old"])
        // The status travels with the date so rows never recompute it.
        #expect(split.comingUp.map(\.status) == [.today, .upcoming(days: 7), .upcoming(days: 88)])
        #expect(split.anniversary == nil)
    }

    @MainActor
    @Test func datesOnTheSameDayBreakTheTieOnTitleRatherThanArbitrarily() {
        let christmas = SpecialDate(title: "Christmas", date: day(2026, 12, 25))
        let birthday = SpecialDate(title: "Anna's birthday", date: day(2026, 12, 25))

        let forwards = SpecialDateSchedule.ordered([christmas, birthday],
                                                   from: day(2026, 8, 7), calendar: calendar)
        let backwards = SpecialDateSchedule.ordered([birthday, christmas],
                                                    from: day(2026, 8, 7), calendar: calendar)

        #expect(forwards.comingUp.map(\.date.title) == ["Anna's birthday", "Christmas"])
        #expect(backwards.comingUp.map(\.date.title) == forwards.comingUp.map(\.date.title))
    }

    // MARK: Anchor normalization

    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    /// The whole point of the anchor convention: a date picked in one timezone
    /// reads as the same civil day in every other one, including the extremes
    /// (UTC−11 through UTC+14, a 25-hour spread that no single instant spans).
    @Test func aPickedDayReadsAsTheSameDayInEveryTimezone() {
        let readers = ["Pacific/Kiritimati",   // UTC+14, the earliest
                       "Asia/Shanghai",
                       "Europe/London",
                       "America/New_York",
                       "Pacific/Midway"]       // UTC−11, the latest

        // Pick from each timezone, at the two times of day that used to break it.
        for picker in readers {
            for hour in [0, 7, 23] {
                let pickerCalendar = calendar(picker)
                let picked = pickerCalendar.date(
                    from: DateComponents(year: 2026, month: 8, day: 14, hour: hour))!
                let stored = SpecialDateSchedule.anchor(for: picked, calendar: pickerCalendar)

                for reader in readers {
                    let readerCalendar = calendar(reader)
                    let day = SpecialDateSchedule.localDay(of: stored, calendar: readerCalendar)
                    let parts = readerCalendar.dateComponents([.year, .month, .day], from: day)
                    #expect(parts.year == 2026 && parts.month == 8 && parts.day == 14,
                            "picked \(hour):00 in \(picker), read in \(reader) as \(parts)")
                }
            }
        }
    }

    @Test func countdownsAgreeAcrossTimezonesForTheSameStoredDate() {
        let shanghai = calendar("Asia/Shanghai")
        let picked = shanghai.date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 7))!
        let stored = SpecialDateSchedule.anchor(for: picked, calendar: shanghai)

        // "Today" is the same civil day for both readers, so the count must match.
        for reader in ["Asia/Shanghai", "America/New_York", "Pacific/Kiritimati"] {
            let readerCalendar = calendar(reader)
            let today = readerCalendar.date(
                from: DateComponents(year: 2026, month: 8, day: 7, hour: 9))!
            #expect(SpecialDateSchedule.status(of: stored, repeatsYearly: false,
                                               from: today, calendar: readerCalendar)
                    == .upcoming(days: 7), "disagreed in \(reader)")
        }
    }

    @MainActor
    @Test func orderedSkipsTombstonedRows() {
        let live = SpecialDate(title: "Live", date: day(2026, 8, 14))
        let deleted = SpecialDate(title: "Deleted", date: day(2026, 8, 10))
        deleted.deletedAt = .now

        let split = SpecialDateSchedule.ordered([live, deleted],
                                                from: day(2026, 8, 7),
                                                calendar: calendar)

        #expect(split.comingUp.map(\.date.title) == ["Live"])
        #expect(split.passed.isEmpty)
        #expect(split.anniversary == nil)
    }

    // MARK: The anniversary

    @MainActor
    @Test func theAnniversaryComesBackInItsOwnGroupAndNotInComingUp() {
        let anniversary = SpecialDate(title: "", date: day(2023, 5, 21),
                                      repeatsYearly: true, isAnniversary: true)
        let birthday = SpecialDate(title: "Her birthday", date: day(2000, 8, 14),
                                   repeatsYearly: true)

        let split = SpecialDateSchedule.ordered([birthday, anniversary],
                                                from: day(2026, 8, 7), calendar: calendar)

        #expect(split.anniversary?.date === anniversary)
        #expect(split.comingUp.map(\.date.title) == ["Her birthday"])
        #expect(split.passed.isEmpty)
    }

    @MainActor
    @Test func aSecondFlaggedRowFallsBackToBeingANormalDate() {
        let first = SpecialDate(title: "First", date: day(2023, 5, 21),
                                repeatsYearly: true, isAnniversary: true)
        let stray = SpecialDate(title: "Stray", date: day(2024, 1, 2),
                                repeatsYearly: true, isAnniversary: true)

        let split = SpecialDateSchedule.ordered([stray, first],
                                                from: day(2026, 8, 7), calendar: calendar)

        // Earliest wins; the extra one is visible rather than silently hidden.
        #expect(split.anniversary?.date.title == "First")
        #expect(split.comingUp.map(\.date.title) == ["Stray"])
    }

    @MainActor
    @Test func theAnniversaryStillBadgesTheHomeTile() {
        let anniversary = SpecialDate(title: "", date: day(2023, 8, 10),
                                      repeatsYearly: true, isAnniversary: true)
        #expect(SpecialDateSchedule.badge(for: [anniversary],
                                          from: day(2026, 8, 7),
                                          calendar: calendar) == .upcoming(days: 3))
    }

    @MainActor
    @Test func aNearerNormalDateBeatsTheAnniversaryForTheBadge() {
        let anniversary = SpecialDate(title: "", date: day(2023, 8, 10),
                                      repeatsYearly: true, isAnniversary: true)
        let sooner = SpecialDate(title: "Sooner", date: day(2026, 8, 8))
        #expect(SpecialDateSchedule.badge(for: [anniversary, sooner],
                                          from: day(2026, 8, 7),
                                          calendar: calendar) == .upcoming(days: 1))
    }

    @MainActor
    @Test func onlyTheAnniversaryIsUndeletable() {
        let anniversary = SpecialDate(title: "", date: day(2023, 5, 21),
                                      repeatsYearly: true, isAnniversary: true)
        let normal = SpecialDate(title: "Kyoto", date: day(2026, 9, 2))
        #expect(anniversary.canDelete == false)
        #expect(normal.canDelete)
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
