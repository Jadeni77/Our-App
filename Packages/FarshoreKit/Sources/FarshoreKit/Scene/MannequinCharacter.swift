import Foundation
import SceneKit
import UIKit

/// A code-built human placeholder, standing in until the owner's Mixamo
/// export lands (see `CharacterLoader`'s drop-in contract). Built entirely
/// from SceneKit primitives — no downloaded asset, no account anywhere, no
/// network dependency (task brief, principle 3): a sphere for the head,
/// capsules for the torso, arms and legs, the limbs on pivot nodes at the
/// shoulders and hips so they can swing from the joint rather than through
/// their own centre.
///
/// Roughly 1.75 m tall and human-proportioned, but **not** anatomically
/// exact — the brief's own bar is "clearly a walking person", not character
/// art, and a placeholder that tried harder than that would be time spent on
/// a model this task deletes the moment a real one exists.
public final class MannequinCharacter: Character {
    public let node = SCNNode()

    // The vertical skeleton lives in `CharacterProportions`, not here — the
    // follow camera has to aim at this body, and a camera aiming by one set
    // of numbers at a body built from another is how the aim point ended up
    // on the character's forehead with a comment claiming it was the chest.
    // Only the widths and limb lengths, which nothing outside this file has
    // any reason to know, are local.
    private static let hipOffsetX: Double = 0.14
    private static let shoulderOffsetX: Double = 0.19
    private static let armLength: Double = 0.62
    private static let limbRadius: Double = 0.07
    private static let torsoRadius: Double = 0.17

    /// Radians either way. Modest on purpose: the brief asks for "clearly a
    /// walking person", not animation quality, and a wide swing on a boxy
    /// placeholder reads as flailing rather than walking.
    private static let swingAmplitude: Double = 0.55

    /// Metres per full swing cycle (leg fully forward, back through
    /// neutral, fully back, and home again). This is a placeholder gait
    /// with nothing real to tune it against, so it is picked to look like a
    /// stride at `LocomotionRules.walkSpeed`, not measured from anything.
    private static let strideLength: Double = 1.6

    /// How long the limbs take to fold back to a standing pose when the
    /// player stops. Long enough to read as settling rather than snapping,
    /// short enough that it is over before the eye asks why the character is
    /// still moving after the thumb came off the stick.
    private static let settleDuration: TimeInterval = 0.25
    /// Keyed so `setMoving(true)` can cancel a settle still in flight and
    /// hand the pivots straight back to `update(distanceWalked:)`, rather
    /// than leaving an action and a per-frame write fighting over the same
    /// `eulerAngles.x`.
    private static let settleActionKey = "settle-to-neutral"

    private let leftHipPivot = SCNNode()
    private let rightHipPivot = SCNNode()
    private let leftShoulderPivot = SCNNode()
    private let rightShoulderPivot = SCNNode()

    /// The four swinging joints. Internal rather than private so the tests
    /// can read the pose directly instead of guessing at it by walking the
    /// node tree by child index — which is what the probe that measured the
    /// mid-stride freeze had to do, and it is unreadable.
    var limbPivots: [SCNNode] {
        [leftHipPivot, rightHipPivot, leftShoulderPivot, rightShoulderPivot]
    }

    /// Cumulative, session-scoped, never persisted — same as everything else
    /// in slice 2 (P-whatever forbids accumulation across sessions; this
    /// accumulates only across the current one, in memory, to drive gait
    /// phase, and is gone the moment the process is).
    private var totalDistanceWalked: Double = 0

    public init() {
        buildBody()
    }

    /// **The gait stopping is not the same thing as the pose being right.**
    /// This used to be an empty body, on the reasoning that `PlayerNode.step`
    /// stops calling `update(distanceWalked:)` the instant the player stops,
    /// so the gait freezes by itself and there was nothing to do. The gait
    /// does freeze — but it freezes *wherever the last frame left it*, which
    /// is a character standing perfectly still with its legs and arms
    /// splayed mid-stride (measured: ±31.5° on all four pivots after a stop).
    /// The brief's "stops dead when the player does" was about the gait not
    /// free-running on wall-clock time. It was never about holding a walk
    /// pose forever.
    public func setMoving(_ moving: Bool) {
        if moving {
            // Cancel any settle still running so `update(distanceWalked:)`
            // gets sole ownership of `eulerAngles.x` back.
            for pivot in limbPivots { pivot.removeAction(forKey: Self.settleActionKey) }
            return
        }

        // Rewind the gait phase as well as the pose. `sin(0)` is 0, which is
        // exactly the neutral stance being eased to — so when walking
        // resumes, the first frame's pose already agrees with where the
        // limbs actually are, and the stride starts from standing instead of
        // snapping back to whatever phase the last stride was interrupted at.
        totalDistanceWalked = 0

        for pivot in limbPivots {
            pivot.removeAction(forKey: Self.settleActionKey)
            pivot.runAction(
                SCNAction.rotateTo(x: 0, y: 0, z: 0,
                                   duration: Self.settleDuration,
                                   usesShortestUnitArc: true),
                forKey: Self.settleActionKey
            )
        }
    }

    public func update(distanceWalked: Double) {
        totalDistanceWalked += distanceWalked
        // Sine of DISTANCE, not of wall-clock time — the brief's explicit
        // requirement. Driving the gait from time would keep the character
        // marching in place on a slope that has slowed movement to a crawl,
        // and would not stop the instant the player does. Driving it from
        // distance means the swing's rate is automatically the walk speed
        // (and whatever `LocomotionRules.slopeFactor` has done to it that
        // frame), and a `distanceWalked` of zero — which is what a stopped
        // player produces, because `PlayerNode.step` stops calling this at
        // all once `travelled` is zero — leaves the phase, and the pose,
        // exactly where they were.
        let phase = totalDistanceWalked / Self.strideLength * (2 * .pi)
        let swing = sin(phase) * Self.swingAmplitude

        // Legs swing opposite each other. Arms swing opposite the legs on
        // THEIR OWN side (left arm forward together with right leg forward)
        // — contralateral, the way people actually walk; swinging same-side
        // limbs together reads as marching, not walking.
        leftHipPivot.eulerAngles.x = Float(swing)
        rightHipPivot.eulerAngles.x = Float(-swing)
        leftShoulderPivot.eulerAngles.x = Float(-swing)
        rightShoulderPivot.eulerAngles.x = Float(swing)
    }

    private func buildBody() {
        let skin = Self.material(color: UIColor(red: 0.80, green: 0.63, blue: 0.52, alpha: 1))
        let clothes = Self.material(color: UIColor(red: 0.25, green: 0.32, blue: 0.42, alpha: 1))

        let hipHeight = CharacterProportions.legLength
        let shoulderHeight = hipHeight + CharacterProportions.torsoLength

        let torso = SCNCapsule(capRadius: Self.torsoRadius, height: CharacterProportions.torsoLength)
        torso.firstMaterial = clothes
        let torsoNode = SCNNode(geometry: torso)
        torsoNode.position = SCNVector3(0, Float(hipHeight + CharacterProportions.torsoLength / 2), 0)
        node.addChildNode(torsoNode)

        let head = SCNSphere(radius: CharacterProportions.headRadius)
        head.firstMaterial = skin
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, Float(shoulderHeight + CharacterProportions.headRadius), 0)
        node.addChildNode(headNode)

        // Legs and arms pivot at the JOINT (hip / shoulder), not at the
        // limb's own centre — `SCNCapsule`'s local origin is its centre, so
        // the capsule node is offset by half its own length inside a pivot
        // node that sits exactly at the joint. Rotating the pivot then
        // swings the limb the way a real leg or arm swings, from its
        // attachment point, rather than through the middle of the thigh.
        leftHipPivot.position = SCNVector3(Float(-Self.hipOffsetX), Float(hipHeight), 0)
        rightHipPivot.position = SCNVector3(Float(Self.hipOffsetX), Float(hipHeight), 0)
        node.addChildNode(leftHipPivot)
        node.addChildNode(rightHipPivot)
        for pivot in [leftHipPivot, rightHipPivot] {
            let leg = SCNCapsule(capRadius: Self.limbRadius, height: CharacterProportions.legLength)
            leg.firstMaterial = clothes
            let legNode = SCNNode(geometry: leg)
            legNode.position = SCNVector3(0, Float(-CharacterProportions.legLength / 2), 0)
            pivot.addChildNode(legNode)
        }

        leftShoulderPivot.position = SCNVector3(Float(-Self.shoulderOffsetX), Float(shoulderHeight), 0)
        rightShoulderPivot.position = SCNVector3(Float(Self.shoulderOffsetX), Float(shoulderHeight), 0)
        node.addChildNode(leftShoulderPivot)
        node.addChildNode(rightShoulderPivot)
        for pivot in [leftShoulderPivot, rightShoulderPivot] {
            let arm = SCNCapsule(capRadius: Self.limbRadius * 0.85, height: Self.armLength)
            arm.firstMaterial = skin
            let armNode = SCNNode(geometry: arm)
            armNode.position = SCNVector3(0, Float(-Self.armLength / 2), 0)
            pivot.addChildNode(armNode)
        }
    }

    /// A plain, untextured material in the same lighting model as
    /// `IslandLook`'s ground and sky — `.physicallyBased` — **not a second
    /// material style** (task brief: must not introduce one). The ground is
    /// textured because it is a real, licensed, scanned asset; the
    /// mannequin has no texture because it is a placeholder for one that
    /// does not exist yet, but it still renders under the same PBR lighting
    /// model as everything else on the island, so it does not look like it
    /// wandered in from a different renderer while it waits to be replaced.
    private static func material(color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        material.roughness.contents = 0.65
        return material
    }
}
