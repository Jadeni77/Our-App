import Foundation
import SceneKit
import os

/// A third-person body `PlayerNode` can wear. Two implementations share this
/// protocol so `PlayerNode` and `IslandSceneView` never have to know which one
/// is in play — that is the whole point of `CharacterLoader` below.
///
/// **Name note:** this shadows `Swift.Character` (the grapheme cluster) inside
/// this module, so any file here that genuinely means a text character must
/// spell it `Swift.Character`. The name was specified by the task brief and is
/// kept for that reason; nothing in FarshoreKit currently does string work at
/// the character level, so the collision costs nothing today.
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

/// **The one place the character's vertical proportions are decided.**
///
/// These were previously spread across two files as unrelated literals, and
/// agreed only by coincidence: `MannequinCharacter` put the centre of the head
/// at `legLength + torsoLength + headRadius`, which happens to come to 1.60,
/// while `PlayerNode.eyeHeight` separately stated `1.6`. Nothing connected
/// them. Retuning `legLength` would have moved the head and left the camera
/// aiming at the height the old head used to be, with a comment still
/// confidently describing the old geometry — the fourth instance in this
/// project of one decision written down as two literals.
///
/// Everything below is derived, so there is exactly one number to change
/// (`totalHeight`) and one skeleton to change it against.
///
/// For a rigged export these are **nominal**: they describe the body the
/// camera is framed for, not a measurement of whatever the owner supplies. A
/// Mixamo character of very different proportions is a reason to revisit
/// `RiggedCharacter.riggedScale`, not to restate a number here.
public enum CharacterProportions {
    /// Heel to crown, metres. The one free parameter.
    public static let totalHeight: Double = 1.75

    public static let headRadius: Double = 0.15
    /// Hip to ground. Also the leg capsule's own length, so a leg hangs from
    /// its pivot exactly to the floor with no gap and no overlap.
    public static let legLength: Double = 0.90
    /// Computed from the other three so the budget always closes:
    /// `legLength + torsoLength + headRadius * 2 == totalHeight`.
    public static var torsoLength: Double { totalHeight - legLength - headRadius * 2 }

    public static var shoulderHeight: Double { legLength + torsoLength }

    /// Centre of the head — where the eyes are on a body whose head is a
    /// sphere. Works out to 1.60 m at the current `totalHeight`, which is the
    /// number `PlayerNode.eyeHeight` used to state independently.
    public static var eyeHeight: Double { shoulderHeight + headRadius }

    /// **Where the follow camera aims.** Mid-torso, not the head.
    ///
    /// Aiming at `eyeHeight` put the camera's target on the centre of the
    /// head, which left the character filling about 30% of frame height with
    /// the top half of the shot almost entirely empty sky. Dropping the aim
    /// point to the middle of the chest centres the body in frame instead of
    /// hanging it off the bottom edge. Works out to ~1.20 m.
    public static var chestHeight: Double { legLength + torsoLength * 0.55 }
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
    ///      `Sources/FarshoreKit/Resources/`. That is the rig, and it is the
    ///      only file that is required.
    ///   3. Add the file's row to `Resources/ASSETS.md` (F9 — every
    ///      third-party asset needs source and licence).
    ///
    /// **Two shapes are supported, because Mixamo hands out one animation per
    /// download.** A single file carrying the rig and its clips works, but it
    /// is not what a real Mixamo hand-over usually looks like. So the clips
    /// may also live in their own files, which is the ordinary SceneKit
    /// pattern for this (Apple's own Fox sample loads a rig and its
    /// animations separately):
    ///
    ///   - `character.scn` — the rig. **Download with skin.** Required.
    ///   - `character-idle.scn` — optional, the idle clip.
    ///   - `character-walk.scn` — optional, the walk clip.
    ///
    /// Each of the two clip files is converted with the same command, just a
    /// different output name. An animation-only export **does not need skin**
    /// — it only has to carry the clip.
    ///
    /// **Precedence: a dedicated clip file beats a same-role clip embedded in
    /// the rig.** Supplying `character-walk.scn` is a deliberate act and the
    /// only reason to do it is to override whatever the rig came with. The
    /// two roles resolve independently, so a rig with a usable idle plus a
    /// separate walk file is fine.
    ///
    /// All four shapes work: rig-with-clips, rig-plus-separate-clips,
    /// rig-alone (renders standing still), and nothing at all (the mannequin).
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
    /// Optional dedicated clip files. See the precedence note above.
    static let idleClipFilename = "character-idle.scn"
    static let walkClipFilename = "character-walk.scn"

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
