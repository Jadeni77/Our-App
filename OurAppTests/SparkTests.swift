import Foundation
import SwiftData
import Testing
@testable import OurApp

@MainActor
struct CheckInRecordTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try Persistence.makeContainer(inMemory: true))
    }

    @Test func aCheckInIsStoredAsAFloatingCivilDay() throws {
        let context = try makeContext()
        CheckInStore.checkIn(in: context, authorID: "me",
                             on: Date(timeIntervalSinceReferenceDate: 800_000_000))

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let stored = try context.fetch(FetchDescriptor<CheckIn>()).first!
        #expect(utc.component(.hour, from: stored.day) == 12)
    }

    @Test func checkingInTwiceOnOneDayWritesOneRow() throws {
        let context = try makeContext()
        let day = Date(timeIntervalSinceReferenceDate: 800_000_000)
        CheckInStore.checkIn(in: context, authorID: "me", on: day)
        // Same civil day, several hours later — a mis-tap, never a second day.
        CheckInStore.checkIn(in: context, authorID: "me", on: day.addingTimeInterval(3600 * 5))

        #expect(try context.fetchCount(FetchDescriptor<CheckIn>()) == 1)
    }

    @Test func daysAreScopedToTheAuthor() throws {
        let context = try makeContext()
        let day = Date(timeIntervalSinceReferenceDate: 800_000_000)
        CheckInStore.checkIn(in: context, authorID: "me", on: day)
        CheckInStore.checkIn(in: context, authorID: "them", on: day)

        // When sync lands both sets exist side by side; the streak must never
        // silently count the other person's days as yours.
        #expect(CheckInStore.days(in: context, authorID: "me").count == 1)
    }

    @Test func aTombstonedCheckInIsNotCounted() throws {
        let context = try makeContext()
        let created = CheckInStore.checkIn(in: context, authorID: "me")
        created.deletedAt = .now
        try context.save()

        #expect(CheckInStore.days(in: context, authorID: "me").isEmpty)
    }
}

struct SparkStreakTests {
    private static let calendars: [Calendar] = {
        ["UTC", "America/Los_Angeles", "America/New_York",
         "Europe/London", "Asia/Shanghai", "Pacific/Kiritimati"].map { name in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: name)!
            return calendar
        }
    }()

    /// Three times of day, because a bug that only shows up near a boundary is
    /// the kind this codebase has already shipped once.
    private static let hours = [0, 12, 23]

    /// Sweeps every timezone × time of day. The body gets a calendar and a
    /// "now", and builds days relative to that same calendar.
    private func sweep(_ body: (Calendar, Date) throws -> Void) rethrows {
        for calendar in Self.calendars {
            for hour in Self.hours {
                let midnight = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 800_000_000))
                let now = calendar.date(byAdding: .hour, value: hour, to: midnight)!
                try body(calendar, now)
            }
        }
    }

    private func days(_ offsets: [Int], from now: Date, _ calendar: Calendar) -> [Date] {
        offsets.map { offset in
            let civil = calendar.date(byAdding: .day, value: offset,
                                      to: calendar.startOfDay(for: now))!
            return SpecialDateSchedule.anchor(for: civil, calendar: calendar)
        }
    }

    @Test func consecutiveDaysEndingTodayCount() throws {
        sweep { calendar, now in
            let status = SparkStreak.status(for: days([0, -1, -2], from: now, calendar),
                                            on: now, calendar: calendar)
            #expect(status.current == 3)
            #expect(status.checkedInToday)
            #expect(status.atRisk == false)
        }
    }

    @Test func yesterdayWithoutTodayIsAliveAndAtRisk() throws {
        sweep { calendar, now in
            let status = SparkStreak.status(for: days([-1, -2, -3], from: now, calendar),
                                            on: now, calendar: calendar)
            // The case the whole feature turns on: the day is not over, so the
            // streak has not broken. Returning 0 here would make the number
            // collapse at every midnight and spring back on tap.
            #expect(status.current == 3)
            #expect(status.atRisk)
            #expect(status.checkedInToday == false)
        }
    }

    @Test func aRunThatEndedTwoDaysAgoIsBroken() throws {
        sweep { calendar, now in
            let status = SparkStreak.status(for: days([-2, -3, -4], from: now, calendar),
                                            on: now, calendar: calendar)
            #expect(status.current == 0)
            #expect(status.atRisk == false)
            // A bad week doesn't erase what a good month was worth.
            #expect(status.longest == 3)
        }
    }

    @Test func theLongestRunSurvivesAGapAndIsNotDoubleCounted() throws {
        sweep { calendar, now in
            let status = SparkStreak.status(for: days([0, -1, -4, -5, -6, -7], from: now, calendar),
                                            on: now, calendar: calendar)
            #expect(status.current == 2)
            #expect(status.longest == 4)
        }
    }

    @Test func noHistoryIsZeroRatherThanACrash() throws {
        sweep { calendar, now in
            #expect(SparkStreak.status(for: [], on: now, calendar: calendar) == .none)
        }
    }

    @Test func aRepeatedDayDoesNotInflateTheStreak() throws {
        sweep { calendar, now in
            // Defence in depth: the store already dedupes, but a duplicate
            // arriving from sync must not count twice either.
            var repeated = days([0, -1], from: now, calendar)
            repeated.append(repeated[0])
            let status = SparkStreak.status(for: repeated, on: now, calendar: calendar)
            #expect(status.current == 2)
        }
    }
}

struct SparkReminderPlanTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    /// 08:00 local, so a 21:00 reminder is still ahead of "now" today.
    private var morning: Date {
        calendar.date(bySettingHour: 8, minute: 0, second: 0,
                      of: Date(timeIntervalSinceReferenceDate: 800_000_000))!
    }

    private var evening: DateComponents { DateComponents(hour: 21, minute: 0) }

    private func day(_ offset: Int) -> Date {
        let civil = calendar.date(byAdding: .day, value: offset,
                                  to: calendar.startOfDay(for: morning))!
        return SpecialDateSchedule.anchor(for: civil, calendar: calendar)
    }

    @Test func anEmptyHistoryFillsTheWholeHorizon() {
        let pending = SparkReminderPlan.pending(from: morning, at: evening,
                                                checkedIn: [], calendar: calendar)
        #expect(pending.count == SparkReminderPlan.horizon)
    }

    @Test func checkingInTodaySilencesTodayAndNothingElse() {
        let pending = SparkReminderPlan.pending(from: morning, at: evening,
                                                checkedIn: [day(0)], calendar: calendar)
        // The point of one request per day rather than a repeating trigger:
        // today goes quiet, tomorrow does not.
        #expect(pending.count == SparkReminderPlan.horizon - 1)
        #expect(!pending.contains { calendar.isDate($0, inSameDayAs: morning) })
    }

    @Test func aTimeAlreadyPastTodayIsNotScheduledInThePast() {
        let lateEvening = calendar.date(bySettingHour: 23, minute: 30, second: 0, of: morning)!
        let pending = SparkReminderPlan.pending(from: lateEvening, at: evening,
                                                checkedIn: [], calendar: calendar)
        // 21:00 has gone; scheduling it would fire the instant the app closes.
        #expect(pending.count == SparkReminderPlan.horizon - 1)
        #expect(pending.allSatisfy { $0 > lateEvening })
    }

    @Test func daysAlreadyCheckedInAreSkippedWhereverTheyFall() {
        let pending = SparkReminderPlan.pending(from: morning, at: evening,
                                                checkedIn: [day(0), day(2), day(5)],
                                                calendar: calendar)
        #expect(pending.count == SparkReminderPlan.horizon - 3)
    }

    @Test func identifiersAreOneADayAndStable() {
        let pending = SparkReminderPlan.pending(from: morning, at: evening,
                                                checkedIn: [], calendar: calendar)
        let ids = pending.map { SparkReminderPlan.identifier(for: $0, calendar: calendar) }
        // Removal-by-identifier is how a check-in silences a day, so a
        // collision would silence the wrong one.
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { $0.hasPrefix(SparkReminderPlan.identifierPrefix) })
    }

    @Test func identifiersDoNotDependOnTheLocalesCalendar() {
        var buddhist = calendar
        buddhist.locale = Locale(identifier: "th_TH_u_ca_buddhist")
        let fire = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: morning)!
        // Built from Gregorian components, not a DateFormatter — a locale that
        // renders 2026 as 2569 would otherwise change every id and orphan every
        // pending request.
        #expect(SparkReminderPlan.identifier(for: fire, calendar: calendar)
                == SparkReminderPlan.identifier(for: fire, calendar: buddhist))
    }
}
