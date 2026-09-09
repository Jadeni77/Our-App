import Foundation

/// Where the survival rules meet the world.
///
/// `Rules/` is pure by construction: `SurvivalRules.step` never reads a wall
/// clock, `ProximityRules` never touches SceneKit, `ForageField.isAvailable`
/// is a function of a timestamp, not a stored counter. None of that is
/// tested by being wired up correctly — only by being correct in isolation.
/// This class is the seam where "correct in isolation" becomes "correct for
/// the player standing at this exact spot, right now": it is the one place
/// that has a real player position, a real clock, and the pure rules all at
/// once, and it is the one place in Tasks 1-5 with tests written against a
/// live instance rather than a bag of static functions. That is deliberate
/// — `CampfireNode` and `ForageNodes` next door render facts the rules
/// already pin and have no tests of their own for exactly that reason; this
/// file is where the wiring itself is the risk.
public final class SurvivalDriver {
    private let fireX: Double
    private let fireZ: Double
    private let seaLevel: Double

    /// The full set the island can offer, fixed for the session. Nothing in
    /// slice 2 adds or removes a forage point while the island is being
    /// played — `ForageField.points` is derived once from the terrain (F2)
    /// and handed in at construction.
    private let points: [ForagePoint]

    public private(set) var state: SurvivalState = .rested

    /// The single nearest reachable point right now, or `nil`. Written only
    /// by `step` — never by `take` — so there is exactly one moment per
    /// frame that decides what "currently offered" means, and it always
    /// reflects an actual position sample rather than something inferred
    /// from stale data.
    public private(set) var offer: ForagePoint?

    /// When each point was last taken, keyed by `ForagePoint.id`. A spring
    /// never gets an entry — see the comment in `take` — so a non-nil entry
    /// here always means "a bush, and it may still be regrowing."
    public private(set) var pickedAt: [Int: Date] = [:]

    public init(fire: (x: Double, z: Double), points: [ForagePoint], seaLevel: Double) {
        fireX = fire.x
        fireZ = fire.z
        self.points = points
        self.seaLevel = seaLevel
    }

    /// Called once per rendered frame. Asks `ProximityRules` the two
    /// questions the render loop is the only place able to answer (where is
    /// the player, how high are they), steps the pure survival maths with
    /// the answers, then recomputes `offer` from whatever is both reachable
    /// and available at `now`.
    public func step(playerX: Double, playerZ: Double, playerHeight: Double,
                     dt: Double, isNight: Bool, now: Date) {
        let nearFire = ProximityRules.isNearFire(playerX: playerX, playerZ: playerZ,
                                                 fireX: fireX, fireZ: fireZ)
        let inSea = ProximityRules.isInSea(playerHeight: playerHeight, seaLevel: seaLevel)
        state = SurvivalRules.step(state, dt: dt, isNight: isNight, nearFire: nearFire, inSea: inSea)

        let available = points.filter { ForageField.isAvailable($0.kind, pickedAt: pickedAt[$0.id], now: now) }
        offer = ProximityRules.reachable(from: (x: playerX, z: playerZ), among: available)
    }

    /// Attempts to pick up `point`. Returns `false`, and changes nothing at
    /// all — not `state`, not `pickedAt` — for anything unavailable or out
    /// of reach.
    ///
    /// **A refusal is a legitimate outcome here, not an error.** The caller
    /// (eventually `ActionButton`, in Task 6) must not treat a tap as having
    /// worked just because it drew a button — this project already paid for
    /// that mistake once on game #1, where a silent no-op that looked
    /// exactly like success cost days. Moonshot M45's rule is the same one
    /// applied here: the store re-checks at the point of truth, the caller
    /// is never the authority.
    ///
    /// Reach is checked against `offer` rather than a fresh position sample,
    /// because `take` is not given a player position by design — "in reach"
    /// is answered exactly once per frame, in `step`, and this spends that
    /// answer rather than asking the question again with no position to ask
    /// it about. That also means two `take` calls between one `step` cannot
    /// both succeed: the first marks the point picked, and the availability
    /// check below — re-derived from the driver's own record, not from
    /// whatever the caller still believes — catches the second.
    @discardableResult
    public func take(_ point: ForagePoint, now: Date) -> Bool {
        guard offer?.id == point.id else { return false }

        // The driver's own record of the point, not the caller's copy —
        // same "do not trust what was handed in" reasoning as the reach
        // check above, aimed at the point's kind and nourishment instead of
        // its position.
        guard let known = points.first(where: { $0.id == point.id }) else { return false }
        guard ForageField.isAvailable(known.kind, pickedAt: pickedAt[known.id], now: now) else { return false }

        state = SurvivalRules.satisfy(state, known.need, by: known.nourishment)

        // A spring is not consumed — `ForageField.isAvailable` returns true
        // for one regardless of `pickedAt` — so recording a pick time for it
        // would be a timestamp nothing ever reads, and worse, a future
        // reader could reasonably take a non-nil `pickedAt` entry to mean
        // "this was exhausted," which is exactly backwards for a spring.
        if known.kind != .spring {
            pickedAt[known.id] = now
        }
        return true
    }

    /// Brings a dead player back to `.rested` — the F3 rule that a blackout
    /// returns you to dawn, reused here for whatever kills you before dawn
    /// actually arrives.
    ///
    /// **Deliberately does not touch `pickedAt` or `offer`.** Restocking the
    /// island on death would turn starving to death into a way to farm a
    /// stripped patch back to full, which is exactly backwards for a
    /// mechanic whose entire point is that death costs you something. The
    /// next `step` call recomputes `offer` from the still-unchanged
    /// `pickedAt` on its own; there is nothing for `revive` to do there.
    public func revive() {
        state = .rested
    }
}
