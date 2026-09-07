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

    // Height budget: legLength + torsoLength + headRadius*2 == totalHeight,
    // by construction (`torsoLength` is computed FROM the other three, not
    // stated as its own literal) — one decision, one place, per the
    // standing lesson about a number restated in two files quietly falling
    // out of sync.
    private static let totalHeight: Double = 1.75
    private static let headRadius: Double = 0.15
    /// Hip to ground. Also the leg capsule's own height and the height at
    /// which the hip pivots sit, so a leg hangs from its pivot exactly to
    /// the floor with no gap and no overlap.
    private static let legLength: Double = 0.90
    private static var torsoLength: Double { totalHeight - legLength - headRadius * 2 }

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

    private let leftHipPivot = SCNNode()
    private let rightHipPivot = SCNNode()
    private let leftShoulderPivot = SCNNode()
    private let rightShoulderPivot = SCNNode()

    /// Cumulative, session-scoped, never persisted — same as everything else
    /// in slice 2 (P-whatever forbids accumulation across sessions; this
    /// accumulates only across the current one, in memory, to drive gait
    /// phase, and is gone the moment the process is).
    private var totalDistanceWalked: Double = 0

    public init() {
        buildBody()
    }

    public func setMoving(_ moving: Bool) {
        // No-op for the mannequin: its gait is driven entirely by
        // `update(distanceWalked:)`, and `PlayerNode.step` simply stops
        // calling that the instant the player stops (see its guard on
        // `travelled > 0`) — the pose freezes mid-stride on its own, with
        // nothing here needing to react to the transition. `RiggedCharacter`
        // is the implementation that actually needs this call, to start or
        // stop an `SCNAnimationPlayer` once rather than every frame.
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

        let hipHeight = Self.legLength
        let shoulderHeight = hipHeight + Self.torsoLength

        let torso = SCNCapsule(capRadius: Self.torsoRadius, height: Self.torsoLength)
        torso.firstMaterial = clothes
        let torsoNode = SCNNode(geometry: torso)
        torsoNode.position = SCNVector3(0, Float(hipHeight + Self.torsoLength / 2), 0)
        node.addChildNode(torsoNode)

        let head = SCNSphere(radius: Self.headRadius)
        head.firstMaterial = skin
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, Float(shoulderHeight + Self.headRadius), 0)
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
            let leg = SCNCapsule(capRadius: Self.limbRadius, height: Self.legLength)
            leg.firstMaterial = clothes
            let legNode = SCNNode(geometry: leg)
            legNode.position = SCNVector3(0, Float(-Self.legLength / 2), 0)
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
