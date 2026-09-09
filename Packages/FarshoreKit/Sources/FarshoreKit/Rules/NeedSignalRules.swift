import Foundation

/// How loudly each need is allowed to speak through the screen.
///
/// The owner rejected meters, rings and numbers, repeatedly (task 6 brief) —
/// the needs speak through the screen itself instead: a warm vignette for
/// thirst, desaturation and a breathing fog for cold, a weaker darkening for
/// hunger. What makes that testable at all is keeping "how strong is this
/// effect right now" and "which need's first lesson is due" as pure
/// functions here, so they can be pinned in a test rather than judged by eye
/// on a simulator this project has been told to leave alone.
///
/// No SwiftUI, no wall clock — same discipline as every other file in
/// `Rules/`.
public enum NeedSignalRules {
    /// Zero until `value` drops below `SurvivalRules.criticalThreshold`,
    /// then ramps linearly to 1 as the need reaches empty. Every
    /// `NeedsFeedback` effect reads this one number for "how strong am I
    /// right now" — one function, not three hand-tuned copies of the same
    /// threshold arithmetic (the brief's rule about one decision never being
    /// two literals in two files).
    public static func intensity(_ value: Double) -> Double {
        let threshold = SurvivalRules.criticalThreshold
        guard threshold > 0, value < threshold else { return 0 }
        guard value > 0 else { return 1 }
        return (threshold - value) / threshold
    }

    /// Hunger's peripheral darkening reads weaker than thirst's vignette —
    /// the task brief's own words. Expressed as a ratio applied to the
    /// shared `intensity`, not as two independently hand-tuned opacities, so
    /// "weaker than" cannot silently invert when either effect gets
    /// restyled later.
    public static let hungerStrengthRelativeToThirst = 0.6

    /// Which need, if any, should block the screen with a first-time card
    /// right now.
    ///
    /// `taught` is the set of needs the player has already dismissed a card
    /// for — never merely shown one (Moonshot M38: a lesson never on screen
    /// was not taught, and the mirror of that, which `FirstTimeCard`
    /// documents, is that a lesson shown but not dismissed was not taught
    /// either).
    ///
    /// Filters to needs that are both **critical** and **untaught**, then
    /// picks the worst of those — deliberately not `SurvivalState.lowest`
    /// directly, which answers a different question ("which need is worst
    /// overall") and can keep pointing at a need that is already taught
    /// (say food, sitting at 0.05) forever, masking a second need (water)
    /// crossing critical later while food is still numerically lower.
    /// Filtering to untaught-and-critical first is what lets every need
    /// still get its own card.
    public static func needForFirstTimeCard(state: SurvivalState, taught: Set<Need>) -> Need? {
        Need.allCases
            .filter { !taught.contains($0) && state.value(of: $0) < SurvivalRules.criticalThreshold }
            .min { state.value(of: $0) < state.value(of: $1) }
    }
}
