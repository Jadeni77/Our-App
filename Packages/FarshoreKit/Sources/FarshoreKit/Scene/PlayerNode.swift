import Foundation
import SceneKit

/// Where the player is. **No physics body** — the ground is a height function,
/// so standing on it is one sample rather than a simulation. That is far
/// cheaper, exactly reproducible, and it cannot fall through the world.
public final class PlayerNode: SCNNode {
    /// Metres from the feet to the character's eyes.
    ///
    /// **Derived, not restated.** This was `1.6`, an independent literal that
    /// agreed with the mannequin's actual head position only by coincidence —
    /// the head centre falls at `legLength + torsoLength + headRadius`, which
    /// happens to come to 1.60. Retuning any of those three would have moved
    /// the head and left this number behind. It now comes from the same
    /// skeleton the body is built from.
    ///
    /// Note this is **not** where the follow camera aims — see
    /// `FollowCamera.lookAtHeight`, which deliberately aims lower.
    public static let eyeHeight: Double = CharacterProportions.eyeHeight

    public private(set) var worldX: Double = 0
    public private(set) var worldZ: Double = 0

    /// Which way the character is pointing, in the same `(sin, cos)` world
    /// convention `LocomotionRules` documents. Distinct from `heading` (the
    /// look/turn direction the drag gesture drives in `FarshoreRootView`,
    /// piped through `IslandSceneView` to `step`'s `heading` parameter):
    /// `heading` steers the camera and re-projects input into world space;
    /// `facing` is a rendering fact about the character, derived FROM the
    /// resulting movement, and the two can legitimately disagree (walking
    /// backward relative to where you're looking still faces the character
    /// the way it is actually walking).
    public private(set) var facing: Double = 0

    private var character: Character?
    private var isMoving = false

    public override init() {
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Adds `character.node` as a child so it inherits this node's world
    /// position for free, and holds the reference so `step` can drive its
    /// gait and idle/moving transitions. Kept separate from `init` because
    /// `IslandSceneView.Coordinator` builds the player before it knows which
    /// `Character` `CharacterLoader.make(in:)` resolved to.
    public func attach(_ character: Character) {
        self.character = character
        addChildNode(character.node)
    }

    public func place(x: Double, z: Double, on terrain: Terrain) {
        worldX = x
        worldZ = z
        settle(on: terrain)
    }

    public func step(input: SIMD2<Double>, heading: Double, dt: Double, terrain: Terrain) {
        let move = LocomotionRules.displacement(input: input, heading: heading, dt: dt)
        let travelled = sqrt(move.x * move.x + move.y * move.y)
        let moving = travelled > 0

        // Called only on a transition (task brief), not every frame — a
        // rigged character's `setMoving` starts/stops an animation player,
        // and doing that 30 times a second per held direction would restart
        // the clip every frame instead of letting it play.
        if moving != isMoving {
            isMoving = moving
            character?.setMoving(moving)
        }

        // Fed the RAW movement vector, not the slope-adjusted one: `move` is
        // already in the `(x, z)` world convention `FacingRules` documents
        // matching `LocomotionRules`' `(sin heading, cos heading)` forward,
        // and facing should track the direction you're trying to walk even
        // on the one frame a slope reduces `factor` toward (but not to)
        // zero — the guard above already sends a true zero vector (no
        // facing change) the frame movement fully stops.
        facing = FacingRules.face(current: facing, towards: move, dt: dt)
        character?.node.eulerAngles.y = Float(facing)

        guard moving else { return }

        let targetX = worldX + move.x
        let targetZ = worldZ + move.y
        let factor = LocomotionRules.slopeFactor(from: terrain.height(atX: worldX, z: worldZ),
                                                 to: terrain.height(atX: targetX, z: targetZ),
                                                 over: travelled)
        worldX += move.x * factor
        worldZ += move.y * factor
        settle(on: terrain)

        // Distance actually travelled this frame, after the slope has had
        // its say — not `travelled`, which is what the flat ground would
        // have allowed. `MannequinCharacter`'s gait is a sine of this value
        // precisely so a climb that `slopeFactor` has slowed to a crawl
        // shows a correspondingly slower stride, not a full-speed one over
        // ground the player isn't actually covering that fast.
        character?.update(distanceWalked: travelled * factor)
    }

    private func settle(on terrain: Terrain) {
        let y = terrain.height(atX: worldX, z: worldZ)
        position = SCNVector3(Float(worldX), Float(y), Float(worldZ))
    }
}
