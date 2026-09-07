import Foundation
import Testing
@testable import FarshoreKit

/// The three questions the survival rules ask about the world. Pure, so the
/// answers can be pinned without a scene.
struct ProximityRulesTests {
    @Test func standingAtTheFireIsNearIt() {
        #expect(ProximityRules.isNearFire(playerX: 100, playerZ: 100, fireX: 100, fireZ: 100))
    }

    @Test func acrossTheIslandIsNotNearTheFire() {
        #expect(ProximityRules.isNearFire(playerX: 400, playerZ: 400, fireX: 100, fireZ: 100) == false)
    }

    /// The boundary itself, because "near the fire" is the difference between
    /// surviving a night and not, and an off-by-one here is a death the player
    /// cannot account for.
    @Test func theWarmthRadiusIsAnInclusiveCircle() {
        let r = ProximityRules.fireWarmthRadius
        #expect(ProximityRules.isNearFire(playerX: r - 0.01, playerZ: 0, fireX: 0, fireZ: 0))
        #expect(ProximityRules.isNearFire(playerX: r + 0.01, playerZ: 0, fireX: 0, fireZ: 0) == false)
    }

    @Test func belowSeaLevelIsInTheSea() {
        #expect(ProximityRules.isInSea(playerHeight: 1.0, seaLevel: 3.0))
        #expect(ProximityRules.isInSea(playerHeight: 5.0, seaLevel: 3.0) == false)
    }

    @Test func theNearestPointInReachIsTheOneOffered() {
        // NOTE: the brief's original values (near at x:10, far at x:11, player
        // at x:10.5) are exactly equidistant (0.5 each) — a tie, not a
        // nearest/farthest pair. `.min(by: <)` keeps the first element it
        // sees on a tie, so with `[far, near]` that tie silently resolved to
        // `far`, and this test failed even against the brief's own
        // unmutated implementation. Moved the player to x:10.2 so `near`
        // (distance 0.2) is unambiguously closer than `far` (distance 0.8),
        // while keeping `far` first in the array so the test still exercises
        // "nearest, not first."
        let near = ForagePoint(id: 1, x: 10, z: 0, kind: .berries)
        let far = ForagePoint(id: 2, x: 11, z: 0, kind: .berries)
        let chosen = ProximityRules.reachable(from: (x: 10.2, z: 0), among: [far, near])
        #expect(chosen?.id == near.id)
    }

    @Test func nothingOutOfReachIsOffered() {
        let far = ForagePoint(id: 1, x: 500, z: 500, kind: .berries)
        #expect(ProximityRules.reachable(from: (x: 0, z: 0), among: [far]) == nil)
    }

    @Test func anEmptyIslandOffersNothing() {
        #expect(ProximityRules.reachable(from: (x: 0, z: 0), among: []) == nil)
    }
}
