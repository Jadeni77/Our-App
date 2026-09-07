import Foundation
import SceneKit
import Testing
@testable import FarshoreKit

/// The parts of the rigged path that can be tested before the owner's export
/// exists. The animation matching cannot be — there is no rig to load — but
/// the container the rig hangs from can, and it is where the two silent
/// assumptions lived: that the export faces local +Z, and that it is authored
/// in metres.
struct RiggedCharacterTests {
    /// **Why the container is two nodes.** `PlayerNode.step` writes
    /// `character.node.eulerAngles.y` every frame. A forward correction
    /// applied to that same node would be overwritten on the first frame and
    /// silently do nothing — so a Mixamo rig facing local −Z would walk
    /// backwards forever, and the constant that was supposed to fix it would
    /// look like it had no effect.
    @Test func theForwardOffsetSurvivesThePerFrameFacingWrite() {
        let rig = SCNNode()
        let container = RiggedCharacter.makeContainer(wrapping: [rig],
                                                      forwardOffset: .pi,
                                                      scale: 1)
        let facing = 0.7

        // Exactly what PlayerNode.step does to the character's node.
        container.eulerAngles.y = Float(facing)

        let f = rig.simdWorldTransform * simd_float4(0, 0, 1, 0)
        let actual = simd_normalize(SIMD2(Double(f.x), Double(f.z)))
        let expected = SIMD2(sin(facing + .pi), cos(facing + .pi))

        #expect(simd_dot(actual, expected) > 0.9999)
    }

    /// A neutral offset must compose to plain facing, or correcting one rig
    /// would quietly mis-aim every other one.
    @Test func aNeutralOffsetLeavesFacingAlone() {
        let rig = SCNNode()
        let container = RiggedCharacter.makeContainer(wrapping: [rig],
                                                      forwardOffset: 0,
                                                      scale: 1)
        let facing = -1.2
        container.eulerAngles.y = Float(facing)

        let f = rig.simdWorldTransform * simd_float4(0, 0, 1, 0)
        let actual = simd_normalize(SIMD2(Double(f.x), Double(f.z)))

        #expect(simd_dot(actual, SIMD2(sin(facing), cos(facing))) > 0.9999)
    }

    /// The 100× case: a centimetre-authored Mixamo export scaled to metres.
    @Test func theScaleCorrectionReachesTheLoadedTree() {
        let rig = SCNNode(geometry: SCNBox(width: 100, height: 175, length: 40,
                                           chamferRadius: 0))
        let container = RiggedCharacter.makeContainer(wrapping: [rig],
                                                      forwardOffset: 0,
                                                      scale: 0.01)

        let box = container.boundingBox
        let height = Double(box.max.y - box.min.y)
        #expect(abs(height - CharacterProportions.totalHeight) < 0.01)
    }

    /// The shipped defaults are neutral, which is the right starting point
    /// for an export nobody has seen yet — but it is a decision, so it is
    /// written down rather than left implied by the absence of a test.
    @Test func theShippedCorrectionsAreNeutralUntilARealExportSaysOtherwise() {
        #expect(RiggedCharacter.riggedForwardOffset == 0)
        #expect(RiggedCharacter.riggedScale == 1)
    }
}
