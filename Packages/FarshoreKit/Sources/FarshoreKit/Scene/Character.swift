import Foundation
import SceneKit

/// A third-person body `PlayerNode` can wear. Two implementations share this
/// protocol so `PlayerNode` and `IslandSceneView` never have to know which one
/// is in play — that is the whole point of `CharacterLoader` below.
public protocol Character: AnyObject {
    /// The node `PlayerNode.attach(_:)` adds as a child. Position and facing
    /// are the parent's job (`PlayerNode` owns world position;
    /// `FacingRules`-derived `eulerAngles.y` is applied by the caller); this
    /// node's own local transform is whatever the implementation needs
    /// internally (the mannequin is built feet-at-origin, for instance).
    var node: SCNNode { get }

    /// Called only on an idle/moving *transition*, not every frame — see
    /// `PlayerNode.step`. A rigged character starts or stops an
    /// `SCNAnimationPlayer` once this way, rather than restarting a clip 30
    /// times a second.
    func setMoving(_ moving: Bool)

    /// Distance walked **this frame**, in metres — not wall-clock time. The
    /// mannequin drives its gait from a sine of this, so the swing matches
    /// however fast the player is actually moving and freezes the instant
    /// they stop, slope and all, rather than animating a walk cycle the feet
    /// aren't keeping up with. A rigged character with real animation clips
    /// is free to ignore the value once it has its own clip-relative timing.
    func update(distanceWalked: Double)
}

/// Prefers a rigged export over the built-in placeholder, so dropping in the
/// owner's Mixamo files is a **file copy with no code change** — that is the
/// entire point of Task 3A (see the task brief's "drop-in contract").
public enum CharacterLoader {
    /// **The drop-in contract.** When the owner's Mixamo export (a rigged
    /// character plus Idle and Walking animations, Collada `.dae` with skin,
    /// from their Adobe account) exists, deploying it is:
    ///
    ///   1. Copy the file into `Sources/FarshoreKit/Resources/`, named
    ///      exactly `character.scn` (if it has been recompiled to SceneKit's
    ///      native format — tried first because it loads faster and needs no
    ///      runtime Collada parsing) **or** `character.dae` (the raw Mixamo
    ///      export, tried second).
    ///   2. Add the file's row to `Resources/ASSETS.md` (F9 — every
    ///      third-party asset needs source and licence).
    ///
    /// That's it. No line in this file, `RiggedCharacter`, or anywhere else
    /// needs to change — this enum is the one place that knows the expected
    /// filenames, so the next person does not have to read the loader to
    /// know what to name their export. The mannequin placeholder disappears
    /// on its own the moment `RiggedCharacter`'s `init?` succeeds.
    static let riggedSceneFilename = "character.scn"
    static let riggedDaeFilename = "character.dae"

    public static func make(in bundle: Bundle) -> Character {
        if let rigged = RiggedCharacter(sceneNamed: riggedSceneFilename, in: bundle) {
            return rigged
        }
        if let rigged = RiggedCharacter(sceneNamed: riggedDaeFilename, in: bundle) {
            return rigged
        }
        return MannequinCharacter()
    }
}
