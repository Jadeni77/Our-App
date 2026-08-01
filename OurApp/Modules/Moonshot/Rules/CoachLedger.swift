import Foundation

/// A contextual teaching beat (M25). Each fires once per partner, keyed by
/// `storageKey` in the seen ledger; replays stay clean.
enum CoachMoment: Equatable {
    case dragToFling
    case goal
    case abilityTap
    case meetCharacter(CharacterID)
    case worldMechanic(Int)

    var storageKey: String {
        switch self {
        case .dragToFling: "drag"
        case .goal: "goal"
        case .abilityTap: "ability"
        case .meetCharacter(let character): "meet-\(character.rawValue)"
        case .worldMechanic(let world): "world-\(world)"
        }
    }
}

/// Decides which coach moments a context deserves. Pure — the seen set
/// comes from Progress, the triggers live at the call sites.
enum CoachLedger {
    /// Ordered moments for a level open: goal → drag (first ever), the
    /// world's mechanic banner (worlds 2+, first entry), then one intro
    /// card per unmet queue member in queue order. Mochi never gets a
    /// card — goal + drag introduce him.
    static func momentsAtLevelOpen(level: MoonshotLevel, seen: Set<String>) -> [CoachMoment] {
        var moments: [CoachMoment] = []
        if !seen.contains(CoachMoment.goal.storageKey) { moments.append(.goal) }
        if !seen.contains(CoachMoment.dragToFling.storageKey) { moments.append(.dragToFling) }
        if level.worldNumber > 1,
           !seen.contains(CoachMoment.worldMechanic(level.worldNumber).storageKey) {
            moments.append(.worldMechanic(level.worldNumber))
        }
        var introduced = Set<CharacterID>()
        for character in level.queue where character != .mochi && !introduced.contains(character) {
            if !seen.contains(CoachMoment.meetCharacter(character).storageKey) {
                moments.append(.meetCharacter(character))
                introduced.insert(character)
            }
        }
        return moments
    }

    /// The in-flight cue: the ability tap, once ever.
    static func momentInFlight(seen: Set<String>) -> CoachMoment? {
        seen.contains(CoachMoment.abilityTap.storageKey) ? nil : .abilityTap
    }
}
