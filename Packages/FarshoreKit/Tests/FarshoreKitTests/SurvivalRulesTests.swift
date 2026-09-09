import Foundation
import Testing
@testable import FarshoreKit

/// The survival maths, kept pure so the balance can be argued with directly
/// rather than felt for on a phone.
///
/// **Everything here is session-scoped (F3).** These rules are stepped by a
/// `dt` the render loop supplies; nothing consults the wall clock and nothing
/// is stored. Time you spend away from the island costs you nothing, which is
/// the whole reason survival and an async shared world can coexist.
struct SurvivalRulesTests {
    private let day = SessionClock.dayLength

    @Test func aRestedStateIsFull() {
        let state = SurvivalState.rested
        #expect(state.warmth == 1)
        #expect(state.water == 1)
        #expect(state.food == 1)
        #expect(state.isDead == false)
    }

    @Test func needsDrainOverTime() {
        let after = SurvivalRules.step(.rested, dt: 60, isNight: false, nearFire: false, inSea: false)
        #expect(after.water < 1)
        #expect(after.food < 1)
        #expect(after.warmth < 1)
    }

    @Test func noTimePassingChangesNothing() {
        #expect(SurvivalRules.step(.rested, dt: 0, isNight: false, nearFire: false, inSea: false) == .rested)
    }

    /// What the `dt > 0` guard actually protects, which is not the zero
    /// case: every drain term is multiplied by `dt`, so a `dt` of 0 changes
    /// nothing whether the guard is there or not. A NEGATIVE `dt` is the
    /// one that needs it — it would run the maths backwards and *refill*
    /// every need, turning a clock that stuttered into a free meal. The
    /// render loop derives `dt` monotonically so it cannot happen from
    /// there today, but `step` is public and the guard is load-bearing for
    /// whoever calls it next.
    @Test func timeRunningBackwardsRefillsNothing() {
        #expect(SurvivalRules.step(.rested, dt: -60, isNight: false, nearFire: false, inSea: false) == .rested)

        let hurt = SurvivalState(warmth: 0.4, water: 0.3, food: 0.2)
        #expect(SurvivalRules.step(hurt, dt: -600, isNight: true, nearFire: true, inSea: false) == hurt)
    }

    /// The tuning anchor the whole balance hangs off: thirst is the first
    /// thing that kills you, and it kills you inside two days. If this ever
    /// stops being true the island stops being tense.
    ///
    /// The loop overshoots the exact "two days" mark by 60 iterations rather
    /// than stopping precisely at `Int(day * 2)`: water is tuned to empty in
    /// exactly 2.0 days, so a loop that stops exactly there depends on 2,400
    /// floating-point subtractions landing precisely on 0 — a flake waiting
    /// to happen. What actually matters is the *ordering* (thirst empties
    /// before hunger), not the exact second it hits zero, so we run past the
    /// mark and still expect water to have bottomed out and food to still
    /// have some left.
    @Test func thirstIsTheFirstNeedToRunOut() {
        var state = SurvivalState.rested
        for _ in 0..<(Int(day * 2) + 60) {
            state = SurvivalRules.step(state, dt: 1, isNight: false, nearFire: false, inSea: false)
        }
        #expect(state.water == 0)
        #expect(state.food > 0)
    }

    /// Night is when warmth becomes the problem — which is what makes getting
    /// back to the fire before dark the shape of a session.
    @Test func nightDrainsWarmthFasterThanDay() {
        let byDay = SurvivalRules.step(.rested, dt: 60, isNight: false, nearFire: false, inSea: false)
        let byNight = SurvivalRules.step(.rested, dt: 60, isNight: true, nearFire: false, inSea: false)
        #expect(byNight.warmth < byDay.warmth)
    }

    /// Only warmth. A cold night does not make you hungrier.
    @Test func nightDoesNotChangeHungerOrThirst() {
        let byDay = SurvivalRules.step(.rested, dt: 60, isNight: false, nearFire: false, inSea: false)
        let byNight = SurvivalRules.step(.rested, dt: 60, isNight: true, nearFire: false, inSea: false)
        #expect(byNight.water == byDay.water)
        #expect(byNight.food == byDay.food)
    }

    /// The sea is the fastest way to die here, deliberately: it is the one
    /// hazard reachable in the first minute, and it teaches that the island
    /// has edges without a wall or a warning. That claim is an *ordering*
    /// between two multipliers, so it has to be tested against the night
    /// rather than against fair daylight — the version of this test that
    /// passed `isNight: false` on both sides compared the sea to a mild
    /// afternoon, left `seaWarmthMultiplier` entirely unguarded, and stayed
    /// green when the sea was made warmer than a dry night.
    @Test func theSeaIsColderThanTheNight() {
        let inSea = SurvivalRules.step(.rested, dt: 60, isNight: false, nearFire: false, inSea: true)
        let atNight = SurvivalRules.step(.rested, dt: 60, isNight: true, nearFire: false, inSea: false)
        #expect(inSea.warmth < atNight.warmth)
    }

    @Test func theFireRestoresWarmth() {
        let cold = SurvivalState(warmth: 0.3, water: 1, food: 1)
        let warmed = SurvivalRules.step(cold, dt: 10, isNight: true, nearFire: true, inSea: false)
        #expect(warmed.warmth > cold.warmth)
    }

    /// The fire cannot overfill you, and a need cannot go negative — every
    /// consumer reads these as 0...1 and a value outside it would render as a
    /// bar past its end or an effect that never clears.
    @Test func needsStayWithinZeroAndOne() {
        let warmed = SurvivalRules.step(.rested, dt: 10_000, isNight: false, nearFire: true, inSea: false)
        #expect(warmed.warmth == 1)

        var starved = SurvivalState.rested
        for _ in 0..<Int(day * 10) {
            starved = SurvivalRules.step(starved, dt: 1, isNight: true, nearFire: false, inSea: true)
        }
        #expect(starved.warmth == 0)
        #expect(starved.water == 0)
        #expect(starved.food == 0)
    }

    @Test func anyNeedAtZeroIsDeath() {
        #expect(SurvivalState(warmth: 0, water: 1, food: 1).isDead)
        #expect(SurvivalState(warmth: 1, water: 0, food: 1).isDead)
        #expect(SurvivalState(warmth: 1, water: 1, food: 0).isDead)
        #expect(SurvivalState(warmth: 0.01, water: 0.01, food: 0.01).isDead == false)
    }

    @Test func theLowestNeedIsWhatIsAboutToKillYou() {
        #expect(SurvivalState(warmth: 0.9, water: 0.2, food: 0.5).lowest == .water)
        #expect(SurvivalState(warmth: 0.1, water: 0.2, food: 0.5).lowest == .warmth)
    }

    @Test func satisfyingANeedRaisesOnlyThatNeed() {
        let thirsty = SurvivalState(warmth: 0.5, water: 0.2, food: 0.5)
        let drunk = SurvivalRules.satisfy(thirsty, .water, by: 0.5)
        #expect(abs(drunk.water - 0.7) < 0.0001)
        #expect(drunk.warmth == 0.5)
        #expect(drunk.food == 0.5)
    }

    @Test func satisfyingCannotOverfill() {
        let full = SurvivalRules.satisfy(.rested, .water, by: 0.9)
        #expect(full.water == 1)
    }
}
