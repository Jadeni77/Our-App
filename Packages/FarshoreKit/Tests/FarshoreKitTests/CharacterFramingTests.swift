import Foundation
import SceneKit
import Testing
@testable import FarshoreKit

/// **Where the camera aims, and whether the body it aims at is the body that
/// actually got built.**
///
/// Both halves matter, and they used to be connected by nothing at all. The
/// mannequin put the centre of its head at `legLength + torsoLength +
/// headRadius` — 1.60 m, by coincidence of four unrelated literals — while
/// `PlayerNode.eyeHeight` separately said `1.6` and the camera aimed there,
/// under a comment claiming it was aiming at the chest. Retuning any leg or
/// torso number would have moved the body and left the camera behind, with
/// the comment still describing geometry nobody had re-derived.
struct CharacterFramingTests {
    private func flatTerrain() -> Terrain {
        let n = 33
        return Terrain(field: HeightField(width: n, depth: n,
                                          samples: [UInt8](repeating: 128, count: n * n)),
                       definition: IslandDefinition(assetName: "t", cellSize: 1,
                                                    heightScale: 100, seaLevel: 0))
    }

    /// **The framing bug.** The aim point has to be in the torso. Aiming at
    /// `eyeHeight` put it on the centre of the head, which pushed the body
    /// into the bottom third of the frame and filled the rest with sky.
    @Test func theCameraAimsInsideTheTorsoNotAtTheHead() {
        #expect(FollowCamera.lookAtHeight > CharacterProportions.legLength)
        #expect(FollowCamera.lookAtHeight < CharacterProportions.shoulderHeight)
        #expect(FollowCamera.lookAtHeight < PlayerNode.eyeHeight)
    }

    /// **The cross-file link, pinned.** The camera aims by
    /// `CharacterProportions`; the mannequin is built from it. This measures
    /// the assembled node tree and checks it against the same constants, so
    /// reintroducing a private literal in `MannequinCharacter` — the exact
    /// "one decision, two literals" regression — fails here rather than
    /// silently mis-aiming the camera.
    @Test func theMannequinIsBuiltToTheProportionsTheCameraAimsBy() throws {
        let mannequin = MannequinCharacter()

        let box = mannequin.node.boundingBox
        #expect(abs(Double(box.min.y) - 0) < 0.001)
        #expect(abs(Double(box.max.y) - CharacterProportions.totalHeight) < 0.001)

        // The head is the only sphere in the body.
        let head = try #require(mannequin.node.childNodes.first { $0.geometry is SCNSphere })
        #expect(abs(Double(head.position.y) - PlayerNode.eyeHeight) < 0.001)

        // And the camera is aiming below it, into the torso the body has.
        #expect(Double(head.position.y) > FollowCamera.lookAtHeight)
    }

    /// End-to-end: the camera node, after `follow`, is genuinely pointing at
    /// the aim height — not merely storing a constant that says so. `look(at:)`
    /// aims local −Z, so this reconstructs the direction SceneKit ended up
    /// with and compares it to the direction the framing intends.
    @Test func followPointsTheCameraAtTheAimHeight() {
        let terrain = flatTerrain()
        let player = PlayerNode()
        let camera = FollowCamera()
        player.place(x: 16, z: 16, on: terrain)

        camera.follow(player, heading: 0.7)

        let target = SIMD3<Float>(Float(player.worldX),
                                  player.position.y + Float(FollowCamera.lookAtHeight),
                                  Float(player.worldZ))
        let origin = SIMD3<Float>(camera.position.x, camera.position.y, camera.position.z)
        let intended = simd_normalize(target - origin)

        let forward4 = camera.simdTransform * simd_float4(0, 0, -1, 0)
        let actual = simd_normalize(SIMD3<Float>(forward4.x, forward4.y, forward4.z))

        #expect(abs(actual.x - intended.x) < 0.001)
        #expect(abs(actual.y - intended.y) < 0.001)
        #expect(abs(actual.z - intended.z) < 0.001)

        // And the aim really is below the head — the whole point of I3. A
        // camera above the player looking down at the head would satisfy the
        // direction check above just as well.
        #expect(target.y < player.position.y + Float(PlayerNode.eyeHeight))
    }
}
