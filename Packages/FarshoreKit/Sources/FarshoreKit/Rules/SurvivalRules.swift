import Foundation

/// How the island wears you down. Pure, and stepped by a `dt` the render loop
/// supplies — **nothing here reads a wall clock** (F3). Time spent away from
/// the island costs you nothing, which is what lets a survival loop and an
/// async shared world coexist at all.
public enum SurvivalRules {
    /// How many in-game days each need takes to empty, unattended, in fair
    /// weather. Expressed in days rather than seconds so the balance reads as
    /// a design statement: **thirst kills first, and it kills inside two
    /// days** — that ordering is what makes finding water the first thing you
    /// do, and hunting later a luxury rather than a chore.
    public static let dayLengthsToEmpty: [Need: Double] = [
        .water: 2.0,
        .food: 4.0,
        .warmth: 3.0
    ]

    /// Warmth only. A cold night does not make you hungrier.
    public static let nightWarmthMultiplier = 2.5
    /// The sea is the fastest way to die on this island, deliberately: it is
    /// the one hazard reachable in the first minute, and it teaches that the
    /// island has edges without a wall or a warning.
    public static let seaWarmthMultiplier = 6.0
    /// Full warmth in a minute at the fire. Long enough to be a decision,
    /// short enough that it never becomes waiting.
    public static let fireWarmthPerSecond = 1.0 / 60.0
    /// Below this, the feedback layer speaks up and the first-time card fires.
    public static let criticalThreshold = 0.25

    /// Days-to-empty is a design statement; seconds-to-empty is a
    /// derivation. `SessionClock.dayLength` is read by reference here rather
    /// than restated, because a second literal for "how long is a day" is
    /// exactly the kind of split that let the sky and the clock disagree in
    /// slice 1 — one decision, one place it lives.
    private static func drainPerSecond(_ need: Need) -> Double {
        guard let days = dayLengthsToEmpty[need] else { return 0 }
        return 1.0 / (days * SessionClock.dayLength)
    }

    public static func step(_ state: SurvivalState,
                            dt: Double,
                            isNight: Bool,
                            nearFire: Bool,
                            inSea: Bool) -> SurvivalState {
        guard dt > 0 else { return state }
        var next = state

        next.water = clamp(state.water - drainPerSecond(.water) * dt)
        next.food = clamp(state.food - drainPerSecond(.food) * dt)

        // Warmth is the only need the world modifies, and the multipliers
        // stack: a night swim is exactly as bad as it sounds.
        var warmthRate = drainPerSecond(.warmth)
        if isNight { warmthRate *= nightWarmthMultiplier }
        if inSea { warmthRate *= seaWarmthMultiplier }
        // The fire wins outright rather than being netted off the drain — it
        // has to be unambiguous that standing at it is safe, or a cold night
        // becomes a stalemate nobody can read.
        next.warmth = nearFire
            ? clamp(state.warmth + fireWarmthPerSecond * dt)
            : clamp(state.warmth - warmthRate * dt)

        return next
    }

    /// Drinking, eating, or warming by anything other than the fire.
    public static func satisfy(_ state: SurvivalState, _ need: Need, by amount: Double) -> SurvivalState {
        var next = state
        switch need {
        case .warmth: next.warmth = clamp(state.warmth + amount)
        case .water: next.water = clamp(state.water + amount)
        case .food: next.food = clamp(state.food + amount)
        }
        return next
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
