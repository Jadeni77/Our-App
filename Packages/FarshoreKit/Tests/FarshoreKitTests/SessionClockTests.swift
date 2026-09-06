import Foundation
import Testing
@testable import FarshoreKit

/// **The decision this file exists to enforce is F3: the clock is scoped to the
/// session.** Night, hunger and cold run only while someone is playing. Growth
/// is safe to hand to a timestamp; decay is not — so nothing here is ever
/// persisted, and a new session always starts at dawn.
struct SessionClockTests {
    @Test func aFreshSessionStartsAtDawn() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = SessionClock(startedAt: start)
        #expect(clock.timeOfDay(at: start) == 0)
    }

    @Test func timeOfDayAdvancesThroughTheDay() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = SessionClock(startedAt: start)
        let midday = start.addingTimeInterval(SessionClock.dayLength / 2)
        #expect(abs(clock.timeOfDay(at: midday) - 0.5) < 0.0001)
    }

    @Test func itWrapsIntoTheNextDay() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = SessionClock(startedAt: start)
        let tomorrowMorning = start.addingTimeInterval(SessionClock.dayLength * 1.25)
        #expect(abs(clock.timeOfDay(at: tomorrowMorning) - 0.25) < 0.0001)
    }

    @Test func nightIsTheBackHalfOfTheCycle() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = SessionClock(startedAt: start)
        #expect(clock.isNight(at: start.addingTimeInterval(SessionClock.dayLength * 0.3)) == false)
        #expect(clock.isNight(at: start.addingTimeInterval(SessionClock.dayLength * 0.8)))
    }

    /// **The F3 guarantee, as a test.** Two sessions started days apart are at
    /// exactly the same time of day one minute in. Wall-clock time between
    /// sessions must not leak into the world — that is what would turn a
    /// partner's busy week into damage to your island.
    ///
    /// The offset between the two `startedAt` values is deliberately **not**
    /// a whole number of days: any whole number of days (86,400s) is itself
    /// an exact multiple of `dayLength` (1,200s, since 86,400 / 1,200 = 72),
    /// so a "days apart" offset alone cannot distinguish a correct
    /// session-relative clock from a broken one that computes phase straight
    /// from `now.timeIntervalSince1970 % dayLength` and ignores `startedAt`
    /// — both would land on the same absolute phase and this test would pass
    /// for the wrong reason. The `+ 37` breaks that coincidence: it is not a
    /// multiple of `dayLength`, so the two absolute query instants land at
    /// different phases under the broken implementation while a correct,
    /// session-relative one still reports the same `timeOfDay` for both
    /// (same 60s elapsed since each session's own start).
    @Test func timeBetweenSessionsIsInvisible() {
        let sessionGap: TimeInterval = 4 * 86_400 + 37
        let monday = SessionClock(startedAt: Date(timeIntervalSince1970: 1_000_000))
        let friday = SessionClock(startedAt: Date(timeIntervalSince1970: 1_000_000 + sessionGap))
        let a = monday.timeOfDay(at: Date(timeIntervalSince1970: 1_000_060))
        let b = friday.timeOfDay(at: Date(timeIntervalSince1970: 1_000_000 + sessionGap + 60))
        #expect(abs(a - b) < 0.0000001)
    }

    /// Long enough that dusk means something, short enough that a session is a
    /// session. 20 minutes, per the spec.
    @Test func aDayIsTwentyMinutes() {
        #expect(SessionClock.dayLength == 20 * 60)
    }
}
