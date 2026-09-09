import Foundation
import Testing
@testable import FarshoreKit

/// The pure decisions behind "no meters": how strongly a need's screen
/// effect should show, and which need's first-time card is due. Kept
/// separate from `NeedsFeedback`/`FirstTimeCard` themselves so the actual
/// logic can be pinned in a test instead of judged by eye on a device.
struct NeedSignalRulesTests {
    private let threshold = SurvivalRules.criticalThreshold

    @Test func aNeedAtFullStrengthHasNoIntensity() {
        #expect(NeedSignalRules.intensity(1) == 0)
    }

    @Test func aNeedExactlyAtTheThresholdHasNoIntensity() {
        // The brief is explicit: nothing on screen while the player is
        // fine, and "fine" is defined as at-or-above the threshold, not
        // strictly above it.
        #expect(NeedSignalRules.intensity(threshold) == 0)
    }

    @Test func aNeedJustBelowTheThresholdHasBarelyAnyIntensity() {
        let justBelow = NeedSignalRules.intensity(threshold - 0.001)
        #expect(justBelow > 0)
        #expect(justBelow < 0.01)
    }

    @Test func anEmptyNeedIsAtFullIntensity() {
        #expect(NeedSignalRules.intensity(0) == 1)
    }

    /// The midpoint of the critical range, pinned exactly rather than just
    /// "somewhere between 0 and 1" — this is the number every visual
    /// multiplies its opacity by, so its scale has to be right, not merely
    /// its direction.
    @Test func intensityRampsLinearlyThroughTheCriticalRange() {
        let midpoint = NeedSignalRules.intensity(threshold / 2)
        #expect(abs(midpoint - 0.5) < 0.0001)
    }

    @Test func intensityNeverExceedsOne() {
        #expect(NeedSignalRules.intensity(-5) == 1)
    }

    /// Hunger has to read weaker than thirst at the owner's own request —
    /// pinned as a ratio strictly less than 1 so a future restyle cannot
    /// silently invert it without a test noticing.
    @Test func hungerIsWeakerThanThirst() {
        #expect(NeedSignalRules.hungerStrengthRelativeToThirst > 0)
        #expect(NeedSignalRules.hungerStrengthRelativeToThirst < 1)
    }

    @Test func nothingIsDueWhenEveryNeedIsFine() {
        #expect(NeedSignalRules.needForFirstTimeCard(state: .rested, taught: []) == nil)
    }

    @Test func theOneCriticalNeedIsDue() {
        let state = SurvivalState(warmth: 1, water: threshold - 0.01, food: 1)
        #expect(NeedSignalRules.needForFirstTimeCard(state: state, taught: []) == .water)
    }

    /// A need already taught must not fire its card again, even while it
    /// stays critical.
    @Test func anAlreadyTaughtNeedIsNeverDueAgain() {
        let state = SurvivalState(warmth: 1, water: 0.01, food: 1)
        #expect(NeedSignalRules.needForFirstTimeCard(state: state, taught: [.water]) == nil)
    }

    /// Among several critical, untaught needs, the worst one speaks —
    /// mirrors `SurvivalState.lowest`'s own tie-break reasoning, but over
    /// the untaught subset rather than all three.
    @Test func theWorstUntaughtCriticalNeedIsChosen() {
        let state = SurvivalState(warmth: 0.2, water: 0.05, food: 0.15)
        #expect(NeedSignalRules.needForFirstTimeCard(state: state, taught: []) == .water)
    }

    /// The case `SurvivalState.lowest` alone would get wrong: food is the
    /// numerically lowest need overall, but it is already taught, so water
    /// — critical and untaught — must be the one that fires, not `nil`.
    @Test func anAlreadyTaughtLowestNeedDoesNotMaskAnotherCriticalNeed() {
        let state = SurvivalState(warmth: 1, water: 0.2, food: 0.01)
        #expect(state.lowest == .food)
        #expect(NeedSignalRules.needForFirstTimeCard(state: state, taught: [.food]) == .water)
    }

    @Test func aNeedAboveTheThresholdIsNeverDueEvenIfUntaught() {
        let state = SurvivalState(warmth: 1, water: threshold + 0.01, food: 1)
        #expect(NeedSignalRules.needForFirstTimeCard(state: state, taught: []) == nil)
    }
}
