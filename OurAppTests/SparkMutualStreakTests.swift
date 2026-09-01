import Foundation
import Testing
@testable import OurApp

/// 火花 is a *couple's* streak.
struct SparkMutualStreakTests {
    private let me = "author-a"
    private let her = "author-b"

    private func day(_ offset: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: offset,
                      to: calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 800_000_000)))!
    }

    private func checkIn(_ offset: Int, _ author: String) -> (day: Date, authorID: String) {
        (day: day(offset), authorID: author)
    }

    /// The owner's report: the streak went up when only one of them checked in.
    @Test func onlyDaysWithBothOfYouCount() {
        let days = SparkStreak.sharedDays(
            [checkIn(0, me), checkIn(0, her),   // both — counts
             checkIn(-1, me),                    // just me — does not
             checkIn(-2, her)],                  // just her — does not
            mine: me, theirs: her)
        #expect(days.count == 1)
    }

    /// Showing up alone, every day, forever, is still not a shared streak.
    @Test func aSoloRunCountsForNothing() {
        let mine = (0..<10).map { checkIn(-$0, me) }
        #expect(SparkStreak.sharedDays(mine, mine: me, theirs: her).isEmpty)
    }

    /// **Before there is a partner it is your own days.** A permanent zero on a
    /// freshly installed app reads as broken, not as a rule.
    @Test func withNoPartnerYetItIsYourOwnDays() {
        let days = SparkStreak.sharedDays([checkIn(0, me), checkIn(-1, me)],
                                          mine: me, theirs: nil)
        #expect(days.count == 2)
    }

    /// Two check-ins from the same person on one day are one day, not two.
    @Test func aDayCountsOnceHoweverManyTimesYouTap() {
        let twice = [checkIn(0, me), checkIn(0, me), checkIn(0, her)]
        #expect(SparkStreak.sharedDays(twice, mine: me, theirs: her).count == 1)
    }

    /// The pair's run, end to end, through the rule that reads it.
    @Test func aMutualRunBecomesAStreak() {
        let both = (0..<4).flatMap { [checkIn(-$0, me), checkIn(-$0, her)] }
        let days = SparkStreak.sharedDays(both, mine: me, theirs: her)
        #expect(SparkStreak.status(for: days, on: day(0)).current == 4)
    }

    /// A day she missed breaks the run even though you were there — which is
    /// the entire point, and the thing that was wrong.
    @Test func aDayOnlyOneOfYouMadeBreaksTheRun() {
        var checkIns = (0..<4).flatMap { [checkIn(-$0, me), checkIn(-$0, her)] }
        checkIns.removeAll { $0.day == day(-2) && $0.authorID == her }

        let days = SparkStreak.sharedDays(checkIns, mine: me, theirs: her)
        #expect(SparkStreak.status(for: days, on: day(0)).current == 2)
    }

    /// The same sweep the rest of 火花 gets: a rule about days must not depend
    /// on which side of UTC you are standing.
    @Test func itHoldsInEveryTimezoneWeCareAbout() {
        for name in ["America/New_York", "Asia/Shanghai", "Europe/London",
                     "Pacific/Kiritimati", "Pacific/Midway", "UTC"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: name)!

            let both = (0..<3).flatMap {
                [(day: day(-$0, calendar: calendar), authorID: me),
                 (day: day(-$0, calendar: calendar), authorID: her)]
            }
            let days = SparkStreak.sharedDays(both, mine: me, theirs: her, calendar: calendar)
            let status = SparkStreak.status(for: days, on: day(0, calendar: calendar),
                                            calendar: calendar)
            #expect(status.current == 3, "wrong in \(name)")
        }
    }
}

/// Checking in has to *do* something the moment you do it.
struct SparkCheckInFeedbackTests {
    private let me = "author-a"
    private let her = "author-b"

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset,
                              to: Calendar.current.startOfDay(
                                for: Date(timeIntervalSinceReferenceDate: 800_000_000)))!
    }

    /// **The bug the owner hit.** Making the streak mutual made your own
    /// check-in invisible: the shared set was empty, so the status was `.none`,
    /// so the flame stayed dark and the label stayed "Check in". Tapping again
    /// just wrote another row. The button looked dead.
    @Test func yourOwnCheckInRegistersEvenBeforeTheirs() {
        let status = SparkStreak.status(for: [], mine: [day(0)], on: day(0))
        #expect(status.checkedInToday)
        #expect(status.sharedToday == false)
        #expect(status.current == 0)
    }

    /// And the day only *counts* once you have both been.
    @Test func theDayCountsWhenBothHaveBeen() {
        let status = SparkStreak.status(for: [day(0)], mine: [day(0)], on: day(0))
        #expect(status.checkedInToday)
        #expect(status.sharedToday)
        #expect(status.current == 1)
    }

    /// Their check-in alone leaves you with something to do.
    @Test func theirCheckInDoesNotTickYourBoxForYou() {
        let status = SparkStreak.status(for: [], mine: [], on: day(0))
        #expect(status.checkedInToday == false)
    }

    /// A live run with your half done today: still at risk, because the day is
    /// not complete — but the button must not offer to check you in twice.
    @Test func aHalfDoneDayIsAtRiskButNotUnchecked() {
        let shared = [day(-1), day(-2)]
        let status = SparkStreak.status(for: shared, mine: shared + [day(0)], on: day(0))
        #expect(status.checkedInToday)
        #expect(status.sharedToday == false)
        #expect(status.current == 2)
        #expect(status.atRisk)
    }
}
