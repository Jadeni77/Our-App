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
                                                      scale: 1).container
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
                                                      scale: 1).container
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
                                                      scale: 0.01).container

        let box = container.boundingBox
        let height = Double(box.max.y - box.min.y)
        #expect(abs(height - CharacterProportions.totalHeight) < 0.01)
    }

    // MARK: - Which clip is idle and which is walk

    /// Named clips are matched case-insensitively, whichever order the tree
    /// happens to be walked in.
    @Test func namedClipsAreMatchedByName() {
        #expect(RiggedCharacter.selectClips(keys: ["Idle", "Walking"]) == (0, 1))
        #expect(RiggedCharacter.selectClips(keys: ["Walking", "Idle"]) == (1, 0))
        #expect(RiggedCharacter.selectClips(keys: ["armature|IDLE", "armature|WALK"]) == (0, 1))

        // **Three clips, so both names have to do real work.** With only two,
        // matching "walk" and taking "the other one" as idle gives the right
        // answer whether or not "idle" is matched at all — which a mutation
        // proved, by deleting the idle match and failing nothing. A rig with
        // a third clip is ordinary, and here the fallback would wrongly pick
        // Run as idle.
        #expect(RiggedCharacter.selectClips(keys: ["Run", "Idle", "Walking"]) == (1, 2))
        #expect(RiggedCharacter.selectClips(keys: ["Jump", "Walking", "Idle"]) == (2, 1))
    }

    /// **The unstable pick.** This used to ask a `Dictionary` for
    /// `keys.first { … }`, and `Dictionary.keys` has no specified order — so
    /// a rig with two keys both containing "walk", which is an ordinary way
    /// to name clips, picked an arbitrary one and could pick a different one
    /// on the next launch. Discovery order is deterministic.
    ///
    /// Run repeatedly because an ordering bug that reproduces one time in
    /// four is exactly the kind that gets dismissed as a fluke.
    @Test func theClipPickIsStableWhenSeveralKeysMatch() {
        let keys = ["walk_forward", "walk_back", "walk_slow"]
        for _ in 0..<200 {
            #expect(RiggedCharacter.selectClips(keys: keys).walk == 0)
        }
    }

    /// No legible names — the common Mixamo case, where clips come back as
    /// opaque identifiers like "mixamo.com". Fall back to first and second
    /// found, in discovery order.
    @Test func unnamedClipsFallBackToFirstAndSecondFound() {
        #expect(RiggedCharacter.selectClips(keys: ["mixamo.com", "mixamo.com"]) == (0, 1))
        #expect(RiggedCharacter.selectClips(keys: ["a", "b", "c"]) == (0, 1))
    }

    /// **A single clip must not resolve to both roles.** When it did,
    /// `setMoving` stopped and replayed the same player on every transition,
    /// snapping the character back to frame one each time the stick was
    /// touched or released.
    @Test func aSingleClipDoesNotBecomeBothIdleAndWalk() {
        let one = RiggedCharacter.selectClips(keys: ["mixamo.com"])
        #expect(one.idle == 0)
        #expect(one.walk == nil)

        let named = RiggedCharacter.selectClips(keys: ["Walking"])
        #expect(named.walk == 0)
        #expect(named.idle == nil)
    }

    /// A rig with no clips at all still has to load — a static character is a
    /// bad character, a crash is a bad app.
    @Test func noClipsIsNotAnError() {
        #expect(RiggedCharacter.selectClips(keys: []) == (nil, nil))
    }

    // MARK: - Precedence between a dedicated clip file and the rig's own clips

    /// With no clip files, every role comes from the rig. Three clips, so
    /// "match one and take the other" cannot pass for the wrong reason.
    @Test func withNoClipFilesEveryRoleComesFromTheRig() {
        let r = RiggedCharacter.resolveClips(embeddedKeys: ["Run", "Idle", "Walking"],
                                             hasIdleFile: false, hasWalkFile: false)
        #expect(r.idle == .embedded(1))
        #expect(r.walk == .embedded(2))
    }

    /// **The rule.** A dedicated file wins even when the rig has a perfectly
    /// good clip of that name — the file beating a *named* match, not merely
    /// filling a gap, is the whole point. Supplying the file is a deliberate
    /// act and the only reason to do it is to override the rig.
    @Test func aDedicatedFileBeatsEvenANamedMatchInTheRig() {
        let r = RiggedCharacter.resolveClips(embeddedKeys: ["Run", "Idle", "Walking"],
                                             hasIdleFile: false, hasWalkFile: true)
        #expect(r.walk == .dedicatedFile)
        #expect(r.idle == .embedded(1))
    }

    /// The two roles resolve independently — a rig with a usable idle plus a
    /// separate walk file is an ordinary way for a hand-over to arrive, and so
    /// is the mirror image.
    @Test func theTwoRolesResolveIndependently() {
        let idleOnly = RiggedCharacter.resolveClips(embeddedKeys: ["Run", "Idle", "Walking"],
                                                    hasIdleFile: true, hasWalkFile: false)
        #expect(idleOnly.idle == .dedicatedFile)
        #expect(idleOnly.walk == .embedded(2))

        let both = RiggedCharacter.resolveClips(embeddedKeys: ["Run", "Idle", "Walking"],
                                                hasIdleFile: true, hasWalkFile: true)
        #expect(both.idle == .dedicatedFile)
        #expect(both.walk == .dedicatedFile)
    }

    /// **A role filled by a file must not reserve an embedded clip.** The
    /// first version ran the first-found/second-found fallback over the whole
    /// key list before precedence was applied, so idle claimed index 0 and
    /// then excluded it from walk — even though idle was already coming from a
    /// file. A rig carrying one opaquely-named clip (the `"mixamo.com"` case
    /// this code elsewhere calls common) plus an idle file stranded that clip
    /// entirely, leaving the character with no walk animation at all.
    @Test func anIdleFileDoesNotStrandTheRigsOnlyClip() {
        let r = RiggedCharacter.resolveClips(embeddedKeys: ["mixamo.com"],
                                             hasIdleFile: true, hasWalkFile: false)
        #expect(r.idle == .dedicatedFile)
        #expect(r.walk == .embedded(0))
    }

    /// The mirror case was already correct, which is exactly what made the bug
    /// above an asymmetry rather than a uniform rule, and easy to miss. Pin
    /// both directions so it stays symmetric.
    @Test func aWalkFileDoesNotStrandTheRigsOnlyClipEither() {
        let r = RiggedCharacter.resolveClips(embeddedKeys: ["mixamo.com"],
                                             hasIdleFile: false, hasWalkFile: true)
        #expect(r.idle == .embedded(0))
        #expect(r.walk == .dedicatedFile)
    }

    /// The open role still prefers a clip actually named for it, rather than
    /// grabbing index 0 because it is first.
    @Test func theOpenRoleStillPrefersAClipNamedForIt() {
        let r = RiggedCharacter.resolveClips(embeddedKeys: ["Run", "Idle", "Walking"],
                                             hasIdleFile: true, hasWalkFile: false)
        #expect(r.walk == .embedded(2))
    }

    /// But it must not press an explicitly *idle* clip into service as a walk
    /// cycle. An opaque name is fair game because it claims nothing; a clip
    /// that says "Idle" is claiming something, and there is already an idle.
    @Test func theOpenRoleWillNotBorrowAClipNamedForTheOtherRole() {
        let r = RiggedCharacter.resolveClips(embeddedKeys: ["Idle"],
                                             hasIdleFile: true, hasWalkFile: false)
        #expect(r.idle == .dedicatedFile)
        #expect(r.walk == nil)
    }

    /// The shape this change exists for: a bare rig with no clips of its own,
    /// plus one file per animation.
    @Test func aBareRigPlusTwoClipFilesResolvesEntirelyFromTheFiles() {
        let r = RiggedCharacter.resolveClips(embeddedKeys: [],
                                             hasIdleFile: true, hasWalkFile: true)
        #expect(r.idle == .dedicatedFile)
        #expect(r.walk == .dedicatedFile)
    }

    /// Nothing anywhere is still not an error.
    @Test func aBareRigWithNoClipFilesResolvesToNothing() {
        let r = RiggedCharacter.resolveClips(embeddedKeys: [],
                                             hasIdleFile: false, hasWalkFile: false)
        #expect(r.idle == nil)
        #expect(r.walk == nil)
    }

    /// The shipped defaults are neutral, which is the right starting point
    /// for an export nobody has seen yet — but it is a decision, so it is
    /// written down rather than left implied by the absence of a test.
    @Test func theShippedCorrectionsAreNeutralUntilARealExportSaysOtherwise() {
        #expect(RiggedCharacter.riggedForwardOffset == 0)
        #expect(RiggedCharacter.riggedScale == 1)
    }
}
