import Foundation
import Testing
@testable import FarshoreKit

/// Which way the character is pointing. Pure, because "it spun the wrong way
/// round" is not a thing you want to debug by walking in circles on a phone.
struct FacingRulesTests {
    @Test func standingStillKeepsYourFacing() {
        #expect(FacingRules.face(current: 1.2, towards: SIMD2(0, 0), dt: 0.1) == 1.2)
    }

    @Test func itTurnsTowardsTheDirectionOfTravel() {
        // Facing north (0), walking east (+x) — should move toward +pi/2.
        let next = FacingRules.face(current: 0, towards: SIMD2(1, 0), dt: 0.1)
        #expect(next > 0)
        #expect(next <= .pi / 2)
    }

    /// **The bug this test exists for.** Turning from just-under +pi to
    /// just-over -pi is a hair's turn the short way and almost a full circle
    /// the long way. Naive interpolation takes the long way, and the character
    /// visibly spins on the spot.
    @Test func itTakesTheShortWayAcrossTheWrapPoint() {
        let current = 3.0                      // just under +pi
        let target = SIMD2(sin(-3.0), cos(-3.0))  // just over -pi
        let next = FacingRules.face(current: current, towards: target, dt: 0.05)
        // The short way from 3.0 toward -3.0 goes UP through pi, not down through 0.
        #expect(next > current)
    }

    @Test func itNeverOvershootsTheTarget() {
        // A huge dt must land exactly on the target, not past it and oscillating.
        let next = FacingRules.face(current: 0, towards: SIMD2(1, 0), dt: 100)
        #expect(abs(next - .pi / 2) < 0.0001)
    }

    @Test func alreadyFacingTheRightWayChangesNothing() {
        let next = FacingRules.face(current: .pi / 2, towards: SIMD2(1, 0), dt: 0.1)
        #expect(abs(next - .pi / 2) < 0.0001)
    }
}
