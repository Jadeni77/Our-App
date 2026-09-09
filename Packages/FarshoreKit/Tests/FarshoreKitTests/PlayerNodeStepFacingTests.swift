import Foundation
import SceneKit
import Testing
@testable import FarshoreKit

/// **The chain three sign bugs have already lived in**, driven end to end:
///
///     input -> LocomotionRules.displacement -> atan2 argument order
///           -> FacingRules.face -> eulerAngles.y -> world forward
///
/// The file this replaces was called a wiring test and tested none of the
/// wiring. It built a bare `SCNNode`, set `eulerAngles.y` on it by hand, and
/// compared the result against hardcoded `sin`/`cos` literals — so it pinned
/// Apple's rotation convention, which was never in doubt and is not ours to
/// get wrong. It never constructed a `PlayerNode`, never called `step`, and
/// never invoked `FacingRules` or `LocomotionRules`. Every link that could
/// actually invert was uncovered.
///
/// These tests use no hardcoded angles at all. They walk the player, measure
/// which way it actually went, and check the body is pointing that way — so a
/// sign flip anywhere in the chain, including a clean 180°, fails here.
/// `@MainActor` because these hand a `Character` to `PlayerNode.attach`, and
/// the test target builds in Swift 6 language mode (only the library target
/// pins v5), where passing a non-`Sendable` class across isolation is an
/// error. Pinning the whole suite to the main actor is also just true of scene
/// graph work.
@MainActor
struct PlayerNodeStepFacingTests {
    private let dt = 1.0 / 30.0

    private func flatTerrain() -> Terrain {
        let n = 65
        return Terrain(field: HeightField(width: n, depth: n,
                                          samples: [UInt8](repeating: 128, count: n * n)),
                       definition: IslandDefinition(assetName: "t", cellSize: 1,
                                                    heightScale: 100, seaLevel: 0))
    }

    /// The direction the character's body is pointing, in world space, in the
    /// same `(x, z)` terms `LocomotionRules` works in. `+Z` is the mannequin's
    /// forward: it is the axis its limbs swing toward and away from, and the
    /// axis its nose points along.
    private func worldForward(of character: Character) -> SIMD2<Double> {
        let f = character.node.simdWorldTransform * simd_float4(0, 0, 1, 0)
        return simd_normalize(SIMD2(Double(f.x), Double(f.z)))
    }

    /// Walk with a fixed stick and heading until the turn converges, and
    /// report where the body ended up pointing versus where it actually went.
    private func walk(input: SIMD2<Double>, heading: Double)
        -> (facing: SIMD2<Double>, travelled: SIMD2<Double>) {
        let terrain = flatTerrain()
        let player = PlayerNode()
        let character = MannequinCharacter()
        player.attach(character)
        player.place(x: 32, z: 32, on: terrain)

        let startX = player.worldX, startZ = player.worldZ
        // Long enough for FacingRules' rate limit to converge from facing 0.
        for _ in 0..<200 {
            player.step(input: input, heading: heading, dt: dt, terrain: terrain)
        }
        let travelled = SIMD2(player.worldX - startX, player.worldZ - startZ)
        return (worldForward(of: character), simd_normalize(travelled))
    }

    /// **The one that matters.** Whatever the stick and the camera heading
    /// are, the body ends up pointing along the direction the player actually
    /// moved. Measured, not asserted against a literal — so a 180° error
    /// (which on a front/back symmetric placeholder is invisible on a device)
    /// shows up as a dot product of −1.
    @Test(arguments: [
        (SIMD2<Double>(0, 1), 0.0),        // forward, facing north
        (SIMD2<Double>(0, 1), 1.3),        // forward, camera turned
        (SIMD2<Double>(0, 1), -2.4),       // forward, camera turned the other way
        (SIMD2<Double>(1, 0), 0.0),        // pure strafe right
        (SIMD2<Double>(-1, 0), 2.0),       // pure strafe left, camera turned
        (SIMD2<Double>(0, -1), 0.6),       // backpedalling: facing must follow
                                           // travel, not the camera
        (SIMD2<Double>(0.7, 0.7), 3.0),    // diagonal, near the wrap point
        (SIMD2<Double>(-0.6, -0.8), -3.0), // diagonal, other side of the wrap
    ])
    func theBodyEndsUpFacingTheWayItActuallyWalked(input: SIMD2<Double>, heading: Double) {
        let (facing, travelled) = walk(input: input, heading: heading)
        let alignment = simd_dot(facing, travelled)
        #expect(alignment > 0.999, "body faced \(facing) but travelled \(travelled)")
    }

    /// Backpedalling is the case where `facing` and `heading` legitimately
    /// disagree, and therefore the case that would hide a bug that simply
    /// copied `heading` into the character's rotation. Pin it explicitly.
    @Test func backpedallingFacesTheWayYouWalkNotTheWayYouLook() {
        let heading = 0.6
        let (facing, travelled) = walk(input: SIMD2(0, -1), heading: heading)

        #expect(simd_dot(facing, travelled) > 0.999)

        // The camera's forward, which the body must NOT be copying.
        let look = SIMD2(sin(heading), cos(heading))
        #expect(simd_dot(facing, look) < -0.999)
    }

    /// Standing still must not reset the facing to due north — the character
    /// would spin to face away from you every time you let go of the stick.
    @Test func lettingGoOfTheStickLeavesTheFacingAlone() {
        let terrain = flatTerrain()
        let player = PlayerNode()
        let character = MannequinCharacter()
        player.attach(character)
        player.place(x: 32, z: 32, on: terrain)

        for _ in 0..<200 {
            player.step(input: SIMD2(1, 0), heading: 1.1, dt: dt, terrain: terrain)
        }
        let facingWhileWalking = worldForward(of: character)
        let restingPlace = (player.worldX, player.worldZ)

        for _ in 0..<60 {
            player.step(input: SIMD2(0, 0), heading: 1.1, dt: dt, terrain: terrain)
        }

        #expect(simd_dot(worldForward(of: character), facingWhileWalking) > 0.9999)
        #expect(player.worldX == restingPlace.0)
        #expect(player.worldZ == restingPlace.1)
    }

    /// The turn is rate-limited, not a snap. A character that instantly
    /// assumes its new facing every frame reads as broken, and a single step
    /// of a 180° reversal must cover only `turnRatePerSecond * dt` of it.
    @Test func theTurnIsGradualRatherThanASnap() {
        let terrain = flatTerrain()
        let player = PlayerNode()
        player.attach(MannequinCharacter())
        player.place(x: 32, z: 32, on: terrain)

        // One step, walking due south, starting from a facing of 0 (north).
        player.step(input: SIMD2(0, -1), heading: 0, dt: dt, terrain: terrain)

        #expect(abs(player.facing) <= FacingRules.turnRatePerSecond * dt + 0.0001)
        #expect(abs(player.facing) > 0)
    }

    /// Attaching a second character must remove the first from the scene
    /// graph. Dropping the reference is not enough — the node is retained by
    /// its parent, so the old body would keep rendering at the player's feet,
    /// frozen, and would still be there after the next swap too.
    @Test func attachingASecondCharacterRemovesTheFirst() {
        let player = PlayerNode()
        let first = MannequinCharacter()
        let second = MannequinCharacter()

        player.attach(first)
        player.attach(second)

        #expect(first.node.parent == nil)
        #expect(second.node.parent === player)
        #expect(player.childNodes.count == 1)
    }

    /// The gait is fed the distance actually covered, so it stays in step with
    /// the feet. Zero distance must leave the pose alone rather than advancing
    /// the walk cycle on a character that has not moved.
    @Test func aStandingPlayerDoesNotAdvanceTheGait() {
        let terrain = flatTerrain()
        let player = PlayerNode()
        let character = MannequinCharacter()
        player.attach(character)
        player.place(x: 32, z: 32, on: terrain)

        for _ in 0..<10 {
            player.step(input: SIMD2(0, 1), heading: 0, dt: dt, terrain: terrain)
        }
        let poseWhileWalking = character.limbPivots.map(\.eulerAngles.x)
        #expect(poseWhileWalking.contains { abs($0) > 0.01 })

        // Standing: step should not drive the gait at all. (The settle from
        // `setMoving(false)` is an SCNAction, which does not advance without a
        // renderer, so the pose here is the frozen one — which is exactly what
        // makes the settle necessary, and is covered in MannequinCharacterTests.)
        for _ in 0..<10 {
            player.step(input: SIMD2(0, 0), heading: 0, dt: dt, terrain: terrain)
        }
        #expect(character.limbPivots.map(\.eulerAngles.x) == poseWhileWalking)
    }
}
