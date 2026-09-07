import Foundation
import SceneKit
import Testing
@testable import FarshoreKit

/// **Animations in their own files — the shape a real Mixamo hand-over takes.**
///
/// Mixamo gives you one animation per download, so "copy in your rig and its
/// Idle and Walking clips" almost never means one file. The loader therefore
/// accepts optional `character-idle.scn` and `character-walk.scn` alongside
/// the rig, and a clip from a dedicated file beats a same-role clip embedded
/// in the rig.
///
/// These build real `.scn` files at run time in a temporary bundle and drive
/// `CharacterLoader.make(in:)` over them, so they exercise the actual loading
/// path rather than a stand-in. Nothing is shipped in the repo to support
/// them: iOS can write `.scn` carrying animations and read them back, which
/// is what makes run-time fixtures possible.
struct CharacterClipFileTests {

    // MARK: - Fixtures

    private func makeBundleDirectory() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(UUID().uuidString).bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A rig: a chain of bones carrying **one animation each**, nested one per
    /// level. `clips: []` is a rig with no animations of its own, which is
    /// exactly what a Mixamo "T-pose, with skin" download is.
    ///
    /// One clip per node, nested rather than siblings, so tree-walk order is
    /// unambiguously the order given — `SCNNode.childNodes` preserves
    /// insertion order, whereas a single node's `animationKeys` is not
    /// something to lean on. The first draft of this helper put two clips on
    /// one bone and the resulting discovery order was Run, Walking, Idle,
    /// which made the assertions below look wrong when they were merely
    /// testing a fixture nobody could predict.
    @discardableResult
    private func writeRig(clips: [String], to dir: URL, named name: String) -> Bool {
        let scene = SCNScene()
        let hips = SCNNode(geometry: SCNBox(width: 0.4, height: 1, length: 0.2, chamferRadius: 0))
        hips.name = "Hips"
        scene.rootNode.addChildNode(hips)

        // Nested, so the collector has to recurse to find them all — a real
        // rig's clips are not sitting on the root node.
        var parent = hips
        for clip in clips {
            let bone = SCNNode(geometry: SCNCapsule(capRadius: 0.05, height: 0.5))
            bone.name = "Bone_\(clip)"
            let animation = CABasicAnimation(keyPath: "eulerAngles.x")
            animation.fromValue = -0.5
            animation.toValue = 0.5
            animation.duration = 1
            animation.repeatCount = .infinity
            bone.addAnimation(animation, forKey: clip)
            parent.addChildNode(bone)
            parent = bone
        }
        return scene.write(to: dir.appendingPathComponent(name),
                           options: nil, delegate: nil, progressHandler: nil)
    }

    /// An animation-only export: one clip, no skin needed. Durations are
    /// given so a test can tell *which* clip was harvested — the players
    /// themselves are otherwise indistinguishable from outside.
    @discardableResult
    private func writeClipFile(clips: [(name: String, duration: Double)],
                               to dir: URL, named name: String) -> Bool {
        let scene = SCNScene()
        var parent = scene.rootNode
        for clip in clips {
            let bone = SCNNode()
            bone.name = "Bone_\(clip.name)"
            let animation = CABasicAnimation(keyPath: "eulerAngles.z")
            animation.fromValue = 0.0
            animation.toValue = 0.3
            animation.duration = clip.duration
            animation.repeatCount = .infinity
            bone.addAnimation(animation, forKey: clip.name)
            parent.addChildNode(bone)
            parent = bone
        }
        return scene.write(to: dir.appendingPathComponent(name),
                           options: nil, delegate: nil, progressHandler: nil)
    }

    @discardableResult
    private func writeClipFile(clip: String, to dir: URL, named name: String) -> Bool {
        writeClipFile(clips: [(clip, 1.0)], to: dir, named: name)
    }

    // MARK: - The four supported shapes

    /// Shape 1: nothing supplied. Still the mannequin.
    @Test func noFilesAtAllStillFallsBackToTheMannequin() throws {
        let dir = try makeBundleDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let bundle = try #require(Bundle(url: dir))

        #expect(CharacterLoader.make(in: bundle) is MannequinCharacter)
    }

    /// Shape 2: the rig alone, carrying no clips. Must still load and render
    /// — a static character is a bad character, a crash is a bad app.
    @Test func aRigWithNoClipsAtAllStillLoads() throws {
        let dir = try makeBundleDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(writeRig(clips: [], to: dir, named: CharacterLoader.riggedSceneFilename))
        let bundle = try #require(Bundle(url: dir))

        let character = try #require(CharacterLoader.make(in: bundle) as? RiggedCharacter)
        #expect(character.clipSources.idle == nil)
        #expect(character.clipSources.walk == nil)

        // And driving it must not crash or leave it in a bad state.
        character.setMoving(true)
        character.setMoving(false)
        #expect(character.node.childNodes.isEmpty == false)
    }

    /// Shape 3: one file carrying the rig and its clips. Three clips, so
    /// "match one and take the other" cannot pass for the wrong reason.
    @Test func aRigCarryingItsOwnClipsResolvesFromTheRig() throws {
        let dir = try makeBundleDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(writeRig(clips: ["Run", "Idle", "Walking"],
                         to: dir, named: CharacterLoader.riggedSceneFilename))
        let bundle = try #require(Bundle(url: dir))

        let character = try #require(CharacterLoader.make(in: bundle) as? RiggedCharacter)
        #expect(character.clipSources.idle == .embedded(1))
        #expect(character.clipSources.walk == .embedded(2))
    }

    /// Shape 4: **the one this whole change exists for** — a rig plus one
    /// file per animation, which is what Mixamo actually hands you.
    @Test func aRigPlusSeparateClipFilesResolvesFromTheFiles() throws {
        let dir = try makeBundleDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(writeRig(clips: [], to: dir, named: CharacterLoader.riggedSceneFilename))
        #expect(writeClipFile(clip: "mixamo.com", to: dir, named: CharacterLoader.idleClipFilename))
        #expect(writeClipFile(clip: "mixamo.com", to: dir, named: CharacterLoader.walkClipFilename))
        let bundle = try #require(Bundle(url: dir))

        let character = try #require(CharacterLoader.make(in: bundle) as? RiggedCharacter)
        #expect(character.clipSources.idle == .dedicatedFile)
        #expect(character.clipSources.walk == .dedicatedFile)

        // Attached under keys we control, so nothing downstream depends on
        // Mixamo having named the clip anything in particular — note the clip
        // above is called "mixamo.com", which says nothing at all.
        #expect(character.node.animationKeys.contains(RiggedCharacter.idleClipKey))
        #expect(character.node.animationKeys.contains(RiggedCharacter.walkClipKey))
    }

    // MARK: - Precedence

    /// **The precedence rule against real files.** The rig carries a perfectly
    /// good Walking clip *and* a `character-walk.scn` is supplied. The file
    /// must win: supplying it is a deliberate act, and the only reason to do
    /// it is to override what the rig came with.
    @Test func aDedicatedClipFileBeatsTheSameRoleEmbeddedInTheRig() throws {
        let dir = try makeBundleDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(writeRig(clips: ["Run", "Idle", "Walking"],
                         to: dir, named: CharacterLoader.riggedSceneFilename))
        #expect(writeClipFile(clip: "mixamo.com", to: dir, named: CharacterLoader.walkClipFilename))
        let bundle = try #require(Bundle(url: dir))

        let character = try #require(CharacterLoader.make(in: bundle) as? RiggedCharacter)

        #expect(character.clipSources.walk == .dedicatedFile)
        // ...and the roles resolve independently: idle still comes from the
        // rig, because no idle file was supplied.
        #expect(character.clipSources.idle == .embedded(1))
    }

    /// Half a hand-over — only the walk clip converted so far — must not
    /// break the other role or the load.
    @Test func supplyingOnlyOneClipFileLeavesTheOtherRoleToTheRig() throws {
        let dir = try makeBundleDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(writeRig(clips: ["Idle"], to: dir, named: CharacterLoader.riggedSceneFilename))
        #expect(writeClipFile(clip: "Walking", to: dir, named: CharacterLoader.walkClipFilename))
        let bundle = try #require(Bundle(url: dir))

        let character = try #require(CharacterLoader.make(in: bundle) as? RiggedCharacter)
        #expect(character.clipSources.idle == .embedded(0))
        #expect(character.clipSources.walk == .dedicatedFile)
    }

    /// A clip file that is present but unusable must not take the role down
    /// with it — the rig's own clip is still there and is the right answer.
    /// Fail soft, but see `RiggedCharacter`'s log for why it was ignored.
    @Test func anUnusableClipFileFallsBackToTheRigRatherThanLosingTheRole() throws {
        let dir = try makeBundleDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(writeRig(clips: ["Idle", "Walking"],
                         to: dir, named: CharacterLoader.riggedSceneFilename))
        try Data("not a scene".utf8)
            .write(to: dir.appendingPathComponent(CharacterLoader.walkClipFilename))
        let bundle = try #require(Bundle(url: dir))

        let character = try #require(CharacterLoader.make(in: bundle) as? RiggedCharacter)
        #expect(character.clipSources.walk == .embedded(1))
    }

    /// A dedicated animation export carries one clip, so which one gets
    /// harvested is normally unobservable. If it somehow carries more, the
    /// pick must still be **deterministic** — first in tree-walk order — for
    /// the same reason the rig's own clip pick is: an arbitrary choice that
    /// can differ between launches is not something the owner can reason
    /// about. Durations stand in for identity, since the players are
    /// otherwise indistinguishable from outside.
    @Test func aClipFileCarryingSeveralAnimationsTakesTheFirstDeterministically() throws {
        let dir = try makeBundleDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(writeRig(clips: [], to: dir, named: CharacterLoader.riggedSceneFilename))
        #expect(writeClipFile(clips: [("first", 1.0), ("second", 7.0)],
                              to: dir, named: CharacterLoader.walkClipFilename))
        let bundle = try #require(Bundle(url: dir))

        let character = try #require(CharacterLoader.make(in: bundle) as? RiggedCharacter)
        let player = try #require(character.node.animationPlayer(forKey: RiggedCharacter.walkClipKey))

        #expect(abs(player.animation.duration - 1.0) < 0.001)
    }

    /// The clip filenames are part of the drop-in instructions, in the same
    /// way the rig's is. Rename the constant and the documentation silently
    /// becomes wrong.
    @Test func theClipFilenamesAreTheOnesDocumented() {
        #expect(CharacterLoader.idleClipFilename == "character-idle.scn")
        #expect(CharacterLoader.walkClipFilename == "character-walk.scn")
    }
}
