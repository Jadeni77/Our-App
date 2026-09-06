import Foundation
import Testing
@testable import FarshoreKit

/// Movement maths, kept out of SceneKit so it can be argued with directly.
struct LocomotionRulesTests {
    @Test func fullForwardInputMovesAtWalkSpeed() {
        let move = LocomotionRules.displacement(input: SIMD2(0, 1), heading: 0, dt: 1)
        #expect(abs(move.y - LocomotionRules.walkSpeed) < 0.0001)
        #expect(abs(move.x) < 0.0001)
    }

    /// **Diagonal input must not be faster than straight input.** Normalising
    /// is the fix, and forgetting it is the single most common movement bug in
    /// the genre — it makes running diagonally objectively correct play.
    @Test func diagonalIsNotFasterThanStraight() {
        let straight = LocomotionRules.displacement(input: SIMD2(0, 1), heading: 0, dt: 1)
        let diagonal = LocomotionRules.displacement(input: SIMD2(1, 1), heading: 0, dt: 1)
        let straightLength = sqrt(straight.x * straight.x + straight.y * straight.y)
        let diagonalLength = sqrt(diagonal.x * diagonal.x + diagonal.y * diagonal.y)
        #expect(abs(straightLength - diagonalLength) < 0.0001)
    }

    /// Partial deflection stays partial — a thumb half-over is a walk, not a run.
    @Test func partialInputMovesProportionally() {
        let half = LocomotionRules.displacement(input: SIMD2(0, 0.5), heading: 0, dt: 1)
        #expect(abs(half.y - LocomotionRules.walkSpeed * 0.5) < 0.0001)
    }

    @Test func headingRotatesTheMovement() {
        let east = LocomotionRules.displacement(input: SIMD2(0, 1), heading: .pi / 2, dt: 1)
        #expect(abs(east.x - LocomotionRules.walkSpeed) < 0.0001)
        #expect(abs(east.y) < 0.0001)
    }

    @Test func noInputIsNoMovement() {
        let still = LocomotionRules.displacement(input: SIMD2(0, 0), heading: 0, dt: 1)
        #expect(still.x == 0)
        #expect(still.y == 0)
    }

    /// Uphill is slower, downhill is not faster. Terrain that costs nothing to
    /// climb is terrain the player never reads.
    @Test func slopeSlowsTheClimbButNotTheDescent() {
        #expect(LocomotionRules.slopeFactor(from: 0, to: 0, over: 1) == 1.0)
        #expect(LocomotionRules.slopeFactor(from: 0, to: 1, over: 1) < 1.0)
        #expect(LocomotionRules.slopeFactor(from: 1, to: 0, over: 1) == 1.0)
    }

    @Test func aCliffIsEffectivelyImpassable() {
        #expect(LocomotionRules.slopeFactor(from: 0, to: 10, over: 1) < 0.2)
    }
}
