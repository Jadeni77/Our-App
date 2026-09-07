import Foundation

/// The questions the survival rules ask about where the player is standing.
///
/// Pure and separate from the scene on purpose: "am I near the fire" decides
/// whether you survive the night, and it should be answerable in a test rather
/// than only by walking around.
public enum ProximityRules {
    /// Generous. A fire you have to stand exactly on is a fire you fight
    /// rather than shelter at.
    ///
    /// **Public on purpose**: a later task derives the campfire's light
    /// falloff from this same number, so that what you can *see* by firelight
    /// matches what keeps you *alive* by it. Read this value rather than
    /// restate it — a decision written as two literals in two files is how
    /// slice 1 spent real time chasing disagreements that were never supposed
    /// to exist.
    ///
    /// **The boundary is exclusive**: at exactly `distance == fireWarmthRadius`
    /// you are not near the fire (`isNearFire` compares with a strict `<`).
    /// Physically the boundary is measure-zero and either choice is
    /// defensible, but the light-falloff task inherits this same edge, so
    /// whoever wires that up needs to know which side of the line is warm.
    public static let fireWarmthRadius: Double = 6.0
    /// Arm's length plus a step — close enough that the offer feels like it
    /// belongs to the thing in front of you.
    public static let reachDistance: Double = 2.5

    public static func isNearFire(playerX: Double, playerZ: Double,
                                  fireX: Double, fireZ: Double) -> Bool {
        hypot(playerX - fireX, playerZ - fireZ) < fireWarmthRadius
    }

    public static func isInSea(playerHeight: Double, seaLevel: Double) -> Bool {
        playerHeight < seaLevel
    }

    /// The **nearest** point in reach, not the first one found — with bushes
    /// clustered, "whichever the array happened to list first" produces an
    /// offer that flickers between two bushes as you turn on the spot.
    public static func reachable(from player: (x: Double, z: Double),
                                 among points: [ForagePoint]) -> ForagePoint? {
        points
            .map { ($0, hypot(player.x - $0.x, player.z - $0.z)) }
            .filter { $0.1 <= reachDistance }
            .min { $0.1 < $1.1 }?
            .0
    }
}
