import Foundation

/// A contextual teaching beat (M25). Each fires once per partner, keyed by
/// `storageKey` in the seen ledger; replays stay clean.
enum CoachMoment: Equatable {
    case dragToFling
    case goal
    case abilityTap
    case meetCharacter(CharacterID)
    case worldMechanic(Int)
    case meetGloom(GloomKind)

    var storageKey: String {
        switch self {
        case .dragToFling: "drag"
        case .goal: "goal"
        case .abilityTap: "ability"
        case .meetCharacter(let character): "meet-\(character.rawValue)"
        case .worldMechanic(let world): "world-\(world)"
        case .meetGloom(let kind): "gloom-\(kind.rawValue)"
        }
    }
}

/// Decides which coach moments a context deserves. Pure — the seen set
/// comes from Progress, the triggers live at the call sites.
enum CoachLedger {
    /// Ordered moments for a level open: goal → drag (first ever), the
    /// world's mechanic banner (worlds 2+, first entry), then one intro
    /// card per unmet character — queue members in queue order, then
    /// swap-available ones (owner amendment 2026-07-31: a player who
    /// unlocks Nox at 24★ mid-W2 meets him at the chip, not in W3).
    /// Mochi never gets a card — goal + drag introduce him.
    static func momentsAtLevelOpen(level: MoonshotLevel,
                                   swapCharacters: [CharacterID] = [],
                                   seen: Set<String>) -> [CoachMoment] {
        var moments: [CoachMoment] = []
        if !seen.contains(CoachMoment.goal.storageKey) { moments.append(.goal) }
        if !seen.contains(CoachMoment.dragToFling.storageKey) { moments.append(.dragToFling) }
        if level.worldNumber > 1,
           !seen.contains(CoachMoment.worldMechanic(level.worldNumber).storageKey) {
            moments.append(.worldMechanic(level.worldNumber))
        }
        var introduced = Set<CharacterID>()
        for character in level.queue + swapCharacters
        where character != .mochi && !introduced.contains(character) {
            if !seen.contains(CoachMoment.meetCharacter(character).storageKey) {
                moments.append(.meetCharacter(character))
                introduced.insert(character)
            }
        }
        // One banner per unmet gloom kind (M29) — classic glooms need no
        // introduction.
        var metKinds = Set<GloomKind>()
        for gloom in level.glooms {
            guard let kind = gloom.kind, !metKinds.contains(kind) else { continue }
            if !seen.contains(CoachMoment.meetGloom(kind).storageKey) {
                moments.append(.meetGloom(kind))
                metKinds.insert(kind)
            }
        }
        return moments
    }

    /// The in-flight cue: the ability tap, once ever.
    static func momentInFlight(seen: Set<String>) -> CoachMoment? {
        seen.contains(CoachMoment.abilityTap.storageKey) ? nil : .abilityTap
    }
}
