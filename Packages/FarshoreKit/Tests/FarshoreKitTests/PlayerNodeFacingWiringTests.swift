import Foundation
import SceneKit
import Testing
@testable import FarshoreKit

/// **Why this test exists, beyond `FacingRulesTests`.** `FacingRulesTests`
/// proves `FacingRules.face` computes the right ANGLE. It cannot prove that
/// applying that angle to `eulerAngles.y` actually turns the character's
/// mesh the way the angle means it to — that step depends on SceneKit's own
/// rotation direction, which `FacingRules`' doc comment asserts but does not
/// itself verify.
///
/// This matters concretely for `MannequinCharacter`: its legs swing about
/// their hip pivot's local X axis, which sweeps the local Y-Z plane. If local
/// +Z, after `eulerAngles.y = facing` is applied, does not actually point
/// toward the world direction `FacingRules` computed the angle FOR, the legs
/// swing across the direction of travel instead of along it — a sideways,
/// crab-like walk instead of a forward one. That would be exactly the kind
/// of "faces 90° or 180° off" bug the task brief calls out as the third of
/// its kind in this project, and — because automation here is not allowed to
/// drive the simulator UI or the owner's phone (task context) — it is a bug
/// nobody running these tests could catch by looking at the result. This
/// test catches it by doing the matrix multiplication SceneKit would do and
/// checking the number, instead.
struct PlayerNodeFacingWiringTests {
    @Test func rotatingByFacingPointsLocalForwardAlongTheWalkedDirection() {
        for facing in [0.0, .pi / 6, .pi / 2, 2.1, -1.7, .pi - 0.01] {
            let node = SCNNode()
            node.eulerAngles.y = Float(facing)

            // Local +Z (the axis `MannequinCharacter`'s limb-swing pivots
            // sweep toward and away from), transformed by the node's
            // rotation only — `w: 0` drops any translation, which is moot
            // here anyway since a fresh `SCNNode` has zero position, but
            // makes explicit that this is a DIRECTION, not a point.
            let localForward = simd_float4(0, 0, 1, 0)
            let worldForward = node.simdTransform * localForward

            // The convention `FacingRules` documents, restated as the thing
            // this test actually checks: `LocomotionRules`' world forward at
            // angle `h` is `(sin h, cos h)`.
            let expectedX = Float(sin(facing))
            let expectedZ = Float(cos(facing))
            #expect(abs(worldForward.x - expectedX) < 0.0001)
            #expect(abs(worldForward.z - expectedZ) < 0.0001)
        }
    }
}
