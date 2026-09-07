import Foundation
import SceneKit
import Testing
@testable import FarshoreKit

/// The placeholder's *pose*, which is the part of it a test can actually
/// judge. Nothing here claims the mannequin looks like a person — that needs
/// eyes on a device. What it does claim is that the character is not left
/// standing in a shape a person never stands in.
struct MannequinCharacterTests {
    /// Walk far enough to be somewhere other than neutral, and return how far.
    @discardableResult
    private func walkOffNeutral(_ m: MannequinCharacter) -> Float {
        m.setMoving(true)
        m.update(distanceWalked: 0.4)
        let worst = m.limbPivots.map { abs($0.eulerAngles.x) }.max() ?? 0
        // Premise: the gait really did move the limbs, so "back to neutral"
        // below is a change and not a coincidence.
        #expect(worst > 0.1)
        return worst
    }

    /// **The bug.** `setMoving` was an empty body, so stopping left the legs
    /// and arms wherever the last frame put them — measured at ±31.5° on all
    /// four pivots, held indefinitely. A person who stops walking puts their
    /// feet together; they do not freeze mid-stride like a paused video.
    @Test func stoppingEasesTheLimbsBackToAStandingPose() {
        let m = MannequinCharacter()
        walkOffNeutral(m)

        m.setMoving(false)

        for pivot in m.limbPivots {
            #expect(pivot.action(forKey: "settle-to-neutral") != nil)
        }
    }

    /// The settle must not still be running once walking resumes, or an
    /// `SCNAction` and `update(distanceWalked:)`'s per-frame write end up
    /// fighting over the same `eulerAngles.x` and the gait stutters.
    @Test func resumingCancelsAnySettleStillInFlight() {
        let m = MannequinCharacter()
        walkOffNeutral(m)
        m.setMoving(false)

        m.setMoving(true)

        for pivot in m.limbPivots {
            #expect(pivot.action(forKey: "settle-to-neutral") == nil)
        }
    }

    /// Easing the pose back to neutral without rewinding the gait phase would
    /// mean the first frame of the next walk snapped the limbs from standing
    /// straight back to the interrupted mid-stride angle — trading a frozen
    /// pose for a visible jerk. The phase reset is what makes resuming
    /// continuous.
    @Test func walkingResumesFromTheStandingPoseRatherThanSnapping() {
        let m = MannequinCharacter()
        walkOffNeutral(m)
        m.setMoving(false)

        m.setMoving(true)
        m.update(distanceWalked: 0.001)

        for pivot in m.limbPivots {
            #expect(abs(pivot.eulerAngles.x) < 0.02)
        }
    }

    /// **A 180° facing error must be visible.** On a front/back symmetric
    /// body it is not: a capsule torso and a featureless sphere head render
    /// identically whichever way round they are, so the character can be
    /// walking backwards and look perfectly correct. Since the owner is the
    /// only pair of eyes on this work, the placeholder has to carry something
    /// that tells front from back — hence the nose.
    ///
    /// Pinned as an asymmetry of the actual assembled geometry, not as "a
    /// node called nose exists", so it stays true however the face is built.
    @Test func theBodyIsVisiblyAsymmetricFrontToBack() {
        let box = MannequinCharacter().node.boundingBox
        #expect(Double(box.max.z) > Double(-box.min.z) + 0.02)
    }

    /// And the asymmetry has to point the way the character walks. A marker
    /// on the *back* would be worse than none: it would make a correct facing
    /// look like a bug and send someone off to "fix" it.
    ///
    /// `+Z` is forward — the axis the limbs swing along and the one
    /// `PlayerNode.step` aims at the direction of travel.
    @Test func everyDistinguishingMarkIsOnTheForwardSide() {
        var offsets: [Float] = []
        func collect(_ node: SCNNode, depth: Int) {
            if node.geometry != nil, depth > 0 { offsets.append(node.position.z) }
            for child in node.childNodes { collect(child, depth: depth + 1) }
        }
        collect(MannequinCharacter().node, depth: 0)

        // Premise: something is off-centre at all.
        #expect(offsets.contains { $0 > 0.001 })
        // And nothing is behind the body's midline.
        #expect(!offsets.contains { $0 < -0.001 })
    }

    /// Contralateral gait: the arm swings opposite the leg on its own side.
    /// Pinned because it is the one property of the swing that reads as
    /// *wrong* rather than merely stylised if it inverts — same-side limbs
    /// moving together is marching, not walking — and because the fix above
    /// touches the same four pivots.
    @Test func armsSwingOppositeTheLegsOnTheirOwnSide() {
        let m = MannequinCharacter()
        m.setMoving(true)
        m.update(distanceWalked: 0.4)

        let (leftHip, rightHip, leftShoulder, rightShoulder) =
            (m.limbPivots[0], m.limbPivots[1], m.limbPivots[2], m.limbPivots[3])

        #expect(leftHip.eulerAngles.x * rightHip.eulerAngles.x < 0)
        #expect(leftHip.eulerAngles.x * leftShoulder.eulerAngles.x < 0)
        #expect(rightHip.eulerAngles.x * rightShoulder.eulerAngles.x < 0)
    }
}
