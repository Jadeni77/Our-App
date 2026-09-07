import Foundation

/// Something on the island worth walking to.
public struct ForagePoint: Hashable, Sendable {
    public enum Kind: Sendable, Hashable {
        case berries, spring
    }

    public let id: Int
    public let x: Double
    public let z: Double
    public let kind: Kind

    public init(id: Int, x: Double, z: Double, kind: Kind) {
        self.id = id
        self.x = x
        self.z = z
        self.kind = kind
    }

    public var need: Need {
        switch kind {
        case .berries: return .food
        case .spring: return .water
        }
    }

    /// A handful of berries is a snack, a spring is a proper drink. The
    /// asymmetry is the point: water is easy once you have found it, food is
    /// a running errand until farming (slice 5) makes it stop being one.
    public var nourishment: Double {
        switch kind {
        case .berries: return 0.18
        case .spring: return 0.6
        }
    }
}

/// Where the food and water are.
///
/// **Derived from the terrain, never stored** — the same idea that makes the
/// island itself affordable (F2). Two phones running the same heightmap
/// compute the same bushes, so nothing about them ever has to travel, and
/// slice 6 gains a shared world without gaining a single byte of forage data.
public enum ForageField {
    /// Long enough that stripping one patch matters, short enough that the
    /// island is not permanently poorer for it. Derived from
    /// `SessionClock.dayLength` rather than restated in seconds — a second
    /// literal for "how long is a day" is exactly the split that let the sky
    /// and the clock disagree in slice 1, and it would happen again here if
    /// this were its own number.
    public static let regrowthSeconds: Double = SessionClock.dayLength * 0.75

    /// Slope steep enough that nothing takes root — keeps bushes off cliff
    /// faces where the player can see them and never reach them.
    private static let maxSlope = 0.55

    /// Fixed forever, by construction rather than by discipline. This value
    /// has no meaning of its own — any 64-bit constant would do exactly as
    /// well — but changing it, for any reason, moves every bush and spring on
    /// every island that has ever been played on, which is the one thing this
    /// whole file exists to prevent (see the type's doc comment).
    private static let seed: UInt64 = 0xFA25_0FEE_D5EE_D000

    public static func points(in terrain: Terrain, berries: Int, springs: Int) -> [ForagePoint] {
        var result: [ForagePoint] = []
        result.reserveCapacity(berries + springs)
        // Seeded and fixed. The determinism is load-bearing, not incidental:
        // it is what lets two devices agree without exchanging anything.
        var random = SeededRandom(seed: seed &+ UInt64(terrain.field.width))
        appendPoints(kind: .berries, count: berries, in: terrain, using: &random, into: &result)
        appendPoints(kind: .spring, count: springs, in: terrain, using: &random, into: &result)
        return result
    }

    private static func appendPoints(kind: ForagePoint.Kind,
                                     count: Int,
                                     in terrain: Terrain,
                                     using random: inout SeededRandom,
                                     into result: inout [ForagePoint]) {
        let extent = Double(terrain.field.width - 1) * terrain.definition.cellSize
        var placed = 0
        var attempts = 0
        // Bounded so a pathological island cannot hang the loop. Falling short
        // is survivable; spinning forever is not.
        while placed < count && attempts < count * 400 {
            attempts += 1
            let x = random.nextDouble() * extent
            let z = random.nextDouble() * extent
            let height = terrain.height(atX: x, z: z)
            guard height > terrain.definition.seaLevel else { continue }

            let step = terrain.definition.cellSize
            let dx = terrain.height(atX: x + step, z: z) - terrain.height(atX: x - step, z: z)
            let dz = terrain.height(atX: x, z: z + step) - terrain.height(atX: x, z: z - step)
            guard sqrt(dx * dx + dz * dz) / (2 * step) < maxSlope else { continue }

            result.append(ForagePoint(id: result.count, x: x, z: z, kind: kind))
            placed += 1
        }
    }

    /// **Availability derives from a timestamp; nothing counts anything.**
    /// Same principle as the crops in slice 5: a state you compute cannot
    /// drift, and a state you increment can.
    public static func isAvailable(_ kind: ForagePoint.Kind, pickedAt: Date?, now: Date) -> Bool {
        // A spring is not consumed. Water keeps coming out of it.
        guard kind != .spring else { return true }
        guard let pickedAt else { return true }
        return now.timeIntervalSince(pickedAt) >= regrowthSeconds
    }
}

/// A tiny deterministic generator, so placement is reproducible on every
/// device and in every future build. `SystemRandomNumberGenerator` is not,
/// which is exactly the bug this avoids.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func nextDouble() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
