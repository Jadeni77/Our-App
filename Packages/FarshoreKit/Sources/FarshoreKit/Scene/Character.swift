import Foundation
import SceneKit
import os

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
/// owner's Mixamo character is a **file copy plus one conversion command**,
/// with no code change — that is the entire point of Task 3A (see the task
/// brief's "drop-in contract").
public enum CharacterLoader {
    /// **The drop-in contract.**
    ///
    /// **`.dae` does not work on iOS, and this is not a matter of opinion.**
    /// iOS ships no Collada importer at all. On macOS the importer lives in an
    /// out-of-process XPC service (a failed load there reports, verbatim,
    /// "Failed to retrieve scene from XPC service"); that service does not
    /// exist on iOS, so `SCNScene(url:)` on a perfectly valid `.dae` throws
    /// `nilError` on device and simulator alike. Collada is meant to be
    /// converted to SceneKit's native format at **build time**, not parsed at
    /// runtime. Measured on this machine against a Collada file written by
    /// SceneKit's own macOS exporter:
    ///
    ///     probe_raw.dae:          SCNScene FAILED -> nilError
    ///     probe_scntool_scn.scn:  SCNScene OK
    ///
    /// So the contract for the owner's Mixamo export (a rigged character with
    /// Idle and Walking, downloaded as Collada `.dae` with skin) is:
    ///
    ///   1. **Convert it.** From the repository root, with Xcode installed:
    ///
    ///          xcrun scntool --convert /path/to/mixamo.dae \
    ///                        --format scn \
    ///                        -o Packages/FarshoreKit/Sources/FarshoreKit/Resources/character.scn
    ///
    ///      That exact command was run and its output verified to load on the
    ///      iOS Simulator, with its animation clips intact and still carrying
    ///      their authored names. (`scntool` lives inside Xcode at
    ///      `Developer/usr/bin/scntool`; `xcrun` finds it. `--format scn` is
    ///      accepted even though `scntool --help` lists only dae/c3d/usd*, and
    ///      it is validated — an unknown format is rejected outright with
    ///      "Unknown conversion format".) The equivalent GUI route is to drag
    ///      the `.dae` into Xcode and use **Editor ▸ Convert to SceneKit scene
    ///      file format (.scn)**.
    ///   2. **Name it `character.scn`** and leave it in
    ///      `Sources/FarshoreKit/Resources/`. That is the only filename this
    ///      loader looks for.
    ///   3. Add the file's row to `Resources/ASSETS.md` (F9 — every
    ///      third-party asset needs source and licence).
    ///
    /// That's it. No line in this file, `RiggedCharacter`, or anywhere else
    /// needs to change; the mannequin placeholder disappears on its own the
    /// moment `RiggedCharacter`'s `init?` succeeds.
    ///
    /// `character.dae` is still *looked for*, purely so that a raw export
    /// dropped in by someone who has not read this comment gets a loud,
    /// specific log line telling them to run the command above — rather than
    /// the silent fallback that hid this problem in the first place. It is
    /// not a supported input.
    static let riggedSceneFilename = "character.scn"
    static let riggedDaeFilename = "character.dae"

    private static let log = Logger(subsystem: "FarshoreKit", category: "CharacterLoader")

    public static func make(in bundle: Bundle) -> Character {
        for filename in [riggedSceneFilename, riggedDaeFilename] {
            // Absent is the normal, expected state until the owner supplies
            // an export — silence is right for that, and only that.
            guard let url = RiggedCharacter.resourceURL(for: filename, in: bundle) else { continue }

            if let rigged = RiggedCharacter(sceneNamed: filename, in: bundle) {
                return rigged
            }

            // PRESENT but unusable. Falling back to the mannequin is still
            // correct (principle 7, fail soft — a bad export must not crash
            // the app), but doing it *quietly* is what made a broken drop-in
            // indistinguishable from a drop-in nobody had performed yet.
            if url.pathExtension.lowercased() == "dae" {
                log.error("""
                    \(filename, privacy: .public) is present but iOS has no Collada importer, \
                    so it cannot be loaded and the mannequin placeholder is being used instead. \
                    Convert it once at build time and ship the result: \
                    xcrun scntool --convert \(filename, privacy: .public) --format scn -o character.scn
                    """)
            } else {
                log.error("""
                    \(filename, privacy: .public) is present but SceneKit could not parse it; \
                    falling back to the mannequin placeholder. If this came from Mixamo, \
                    re-run: xcrun scntool --convert <export>.dae --format scn -o character.scn
                    """)
            }
        }
        return MannequinCharacter()
    }
}
