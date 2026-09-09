import Foundation

/// What the island is taking from you.
public enum Need: String, CaseIterable, Sendable {
    case warmth, water, food
}

/// The three needs, as one value.
///
/// A struct rather than three properties on a driver, because every rule that
/// touches them is a pure function from one state to the next — which is what
/// lets the whole balance be argued with in tests instead of felt for on a
/// phone.
public struct SurvivalState: Sendable, Equatable {
    public var warmth: Double
    public var water: Double
    public var food: Double

    public init(warmth: Double, water: Double, food: Double) {
        self.warmth = warmth
        self.water = water
        self.food = food
    }

    /// Where every session begins, and where a blackout returns you (F3): the
    /// clock starts at dawn and so do you.
    public static let rested = SurvivalState(warmth: 1, water: 1, food: 1)

    public func value(of need: Need) -> Double {
        switch need {
        case .warmth: return warmth
        case .water: return water
        case .food: return food
        }
    }

    /// The need about to kill you — what the feedback layer speaks about, so
    /// the player is told one thing rather than three.
    public var lowest: Need {
        Need.allCases.min { value(of: $0) < value(of: $1) } ?? .water
    }

    /// **Any** need at zero, not all three. Dying of thirst with a full
    /// stomach is the normal way to go here.
    public var isDead: Bool {
        warmth <= 0 || water <= 0 || food <= 0
    }
}
