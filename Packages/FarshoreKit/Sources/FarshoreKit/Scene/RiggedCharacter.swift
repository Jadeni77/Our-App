import Foundation
import SceneKit
import os

/// Wraps a rigged export loaded from the app bundle — the owner's Mixamo
/// character plus Idle and Walking animations, or a `.scn` recompiled from
/// it. See `CharacterLoader` for the drop-in contract this exists to serve:
/// this type exists and is fully written *before* the export itself does,
/// because that is the point of Task 3A.
public final class RiggedCharacter: Character {
    public let node: SCNNode

    /// The inner container holding the loaded tree — everything below the
    /// node `PlayerNode` rotates for facing. Clips loaded from dedicated
    /// files are attached **here**, so a clip whose bone names do not resolve
    /// cannot overwrite the character's facing. See the note at the
    /// attachment site.
    let rigNode: SCNNode

    /// Every `SCNAnimationPlayer` found anywhere in the loaded node tree,
    /// keyed by whatever identifier SceneKit assigned on load. **Mixamo
    /// names these unhelpfully** (task brief) — exports commonly come back
    /// as opaque identifiers like `"mixamo.com"` rather than "Idle" or
    /// "Walk" — so nothing here assumes the keys will say anything legible.
    private let animationsByKey: [String: SCNAnimationPlayer]
    /// The same players, in discovery order, for the first/second-found
    /// fallback used when key-matching finds nothing.
    private let animationsByIndex: [SCNAnimationPlayer]

    private let idlePlayer: SCNAnimationPlayer?
    private let walkPlayer: SCNAnimationPlayer?
    private var isMoving = false

    /// Where each role's clip actually came from. Internal so tests can pin
    /// the precedence rule against real loaded files rather than only against
    /// the pure function — and useful on its own when someone is staring at a
    /// character wondering which of their three files is being used.
    let clipSources: (idle: ClipSource?, walk: ClipSource?)

    private static let log = Logger(subsystem: "FarshoreKit", category: "RiggedCharacter")

    /// Keys this type assigns to clips loaded from dedicated files, so
    /// nothing downstream has to match on names Mixamo chose. Namespaced to
    /// avoid colliding with a key the rig already uses.
    static let idleClipKey = "farshore.idle"
    static let walkClipKey = "farshore.walk"

    // MARK: - Assumptions about the export, made explicit
    //
    // Everything below was previously assumed silently: the loaded tree was
    // re-parented with no rotation and no scale correction, which quietly
    // asserts that the export faces local +Z and is authored in metres.
    // Neither is reliably true of a Mixamo download, and both fail in ways
    // that are easy to misread as something else.

    /// Radians about Y applied to the loaded tree *before* the per-frame
    /// facing rotation, to bring the export's own forward axis into line with
    /// this project's, which is **local +Z** (the direction the mannequin's
    /// nose points and its limbs swing along).
    ///
    /// **How to tell you need to change this**, from the owner's chair:
    ///
    ///   - The character moonwalks — glides in the direction it is walking,
    ///     but facing the opposite way: the rig faces local −Z. Set `.pi`.
    ///   - The character crab-walks — travels sideways relative to the way it
    ///     is pointing: the rig faces local ±X. Set `.pi / 2` or `-.pi / 2`;
    ///     try one, and if it is now 180° out, use the other.
    ///   - It looks right: leave it at 0.
    ///
    /// A 180° error is the dangerous one, because on a front/back symmetric
    /// body it looks identical to correct — which is why the mannequin now
    /// has a nose. Check the character's face, not its silhouette.
    public static let riggedForwardOffset: Double = 0

    /// Uniform scale applied to the loaded tree. The rest of this package
    /// works in metres: the ground is metres, `LocomotionRules.walkSpeed` is
    /// 2.8 m/s, and `CharacterProportions.totalHeight` is 1.75 m.
    ///
    /// **Mixamo exports frequently land at 100×**, because the source rig is
    /// authored in centimetres. The symptom is unmistakable once you know it:
    /// the camera sits inside a wall of texture, or the character fills the
    /// entire screen and never appears to move, because a 175 m person takes
    /// a very long time to walk anywhere at 2.8 m/s. Set `0.01`.
    ///
    /// The opposite (an ant-sized character on a correct-looking island)
    /// means the export is in metres but something upstream divided; set
    /// `100`. If in doubt, the loaded tree's bounding box height should come
    /// out near `CharacterProportions.totalHeight`.
    public static let riggedScale: Double = 1

    /// Builds the two-node container the loaded tree hangs from.
    ///
    /// **Two nodes, not one, and that is load-bearing.** `PlayerNode.step`
    /// writes `character.node.eulerAngles.y` every frame to apply facing. If
    /// `riggedForwardOffset` were applied to that same node it would be
    /// overwritten on the very first frame and the correction would silently
    /// do nothing. The outer node is the one the caller rotates; the inner
    /// node carries the export's own correction, underneath, where the
    /// per-frame write cannot reach it.
    ///
    /// The offset and scale are parameters, defaulting to the constants
    /// above, so a test can exercise a non-zero correction. With both at
    /// their current neutral defaults a one-node and a two-node container
    /// behave identically, and the bug this shape exists to prevent would be
    /// untestable.
    ///
    /// Returns both nodes, because callers need to be able to tell them
    /// apart. Anything that must survive the per-frame facing write — the
    /// forward offset, the scale, **and any animation player attached to the
    /// character** — belongs on `rig`, never on `container`.
    static func makeContainer(wrapping children: [SCNNode],
                              forwardOffset: Double = riggedForwardOffset,
                              scale: Double = riggedScale) -> (container: SCNNode, rig: SCNNode) {
        let outer = SCNNode()
        let inner = SCNNode()
        inner.eulerAngles.y = Float(forwardOffset)
        inner.scale = SCNVector3(Float(scale), Float(scale), Float(scale))
        for child in children {
            inner.addChildNode(child)
        }
        outer.addChildNode(inner)
        return (outer, inner)
    }

    /// Where `sceneNamed:in:` would look. Split out so `CharacterLoader` can
    /// tell "no export supplied yet" (silence is correct) from "an export is
    /// sitting right there and did not load" (must be logged) — `init?`
    /// returns `nil` for both and cannot distinguish them from outside, which
    /// is exactly how a `.dae` that iOS cannot parse stayed invisible.
    static func resourceURL(for name: String, in bundle: Bundle) -> URL? {
        let filename = name as NSString
        return bundle.url(forResource: filename.deletingPathExtension,
                          withExtension: filename.pathExtension)
    }

    /// `name` is a full filename (e.g. `"character.scn"`), not a bare
    /// resource name — `CharacterLoader` tries `.scn` then `.dae` and needs
    /// to say which extension it means for each attempt.
    ///
    /// Fails (returns `nil`) if the bundle has no such resource, or if
    /// SceneKit cannot parse what's there. Either way, `CharacterLoader`
    /// falls back to `MannequinCharacter` — **fail soft** (principle 7): a
    /// bad or missing export must degrade to the placeholder, never crash
    /// the app. `CharacterLoader` is responsible for *logging* the
    /// supplied-but-broken case, using `resourceURL(for:in:)` above to tell
    /// the two apart.
    public init?(sceneNamed name: String, in bundle: Bundle) {
        guard let url = Self.resourceURL(for: name, in: bundle) else { return nil }

        // `.doNotPlay`: SceneKit's default animation import policy starts
        // every animation it finds playing immediately on load. A rig
        // carrying both Idle and Walking would then play both at once,
        // blended, forever, with no way to tell which clip is "the" one in
        // play. Loading everything paused and starting the right single
        // clip from `setMoving` is the only way to show one at a time.
        let options: [SCNSceneSource.LoadingOption: Any] = [
            .animationImportPolicy: SCNSceneSource.AnimationImportPolicy.doNotPlay
        ]
        guard let scene = try? SCNScene(url: url, options: options) else { return nil }

        // Re-parent rather than keep `scene.rootNode` itself: `Character`
        // promises callers a `node` they can add as a *child* of
        // `PlayerNode` and rotate for facing (`eulerAngles.y`); handing back
        // a scene's actual root risks a caller finding scene-level state
        // (e.g. a loaded root's own transform, if the export has one) rather
        // than a clean container. The container also carries the export's
        // forward-axis and scale corrections — see `makeContainer`.
        let built = Self.makeContainer(wrapping: scene.rootNode.childNodes)
        self.node = built.container
        self.rigNode = built.rig

        let found = Self.collectAnimationPlayers(under: built.container)
        self.animationsByKey = Dictionary(found.map { ($0.key, $0.player) },
                                          uniquingKeysWith: { first, _ in first })
        self.animationsByIndex = found.map(\.player)

        // Optional sibling clip files. Mixamo hands out **one animation per
        // download**, so the ordinary shape of a real hand-over is a rig plus
        // a file per clip, not one file carrying everything. Absent is the
        // normal case and stays silent.
        let idleFromFile = Self.loadClip(named: CharacterLoader.idleClipFilename, in: bundle)
        let walkFromFile = Self.loadClip(named: CharacterLoader.walkClipFilename, in: bundle)

        // Attach under keys *we* choose, so selection stops depending on
        // whatever Mixamo happened to name the clip inside the file, and so
        // the rest of this type can find them without another name-matching
        // guess.
        //
        // **On `rigNode`, never on `node`.** SceneKit retargets an attached
        // animation by the bone name it carries; when that name does not
        // resolve, it animates *the node the player is attached to* instead.
        // `node` is the outer container, which `PlayerNode.step` writes
        // `eulerAngles.y` to every frame — so attaching here meant a clip
        // whose bone names did not match could silently overwrite the
        // character's facing. Measured, with the model facing set to 1.0:
        //
        //     attached to `node`:    RENDERED root y = 0.393 — facing lost,
        //                            the body spins with the clip instead of
        //                            turning the way it walks.
        //     attached to `rigNode`: RENDERED root y = 1.0   — facing intact.
        //
        // This is the same hazard `makeContainer` exists to prevent for
        // `riggedForwardOffset`. Anything that must survive the per-frame
        // write goes underneath it.
        if let idleFromFile { built.rig.addAnimationPlayer(idleFromFile, forKey: Self.idleClipKey) }
        if let walkFromFile { built.rig.addAnimationPlayer(walkFromFile, forKey: Self.walkClipKey) }

        let resolved = Self.resolveClips(embeddedKeys: found.map(\.key),
                                         hasIdleFile: idleFromFile != nil,
                                         hasWalkFile: walkFromFile != nil)
        self.clipSources = resolved
        idlePlayer = resolved.idle.flatMap { $0.player(fromFile: idleFromFile, embedded: found) }
        walkPlayer = resolved.walk.flatMap { $0.player(fromFile: walkFromFile, embedded: found) }

        // Start in the idle pose — or whatever single clip exists, since
        // playing nothing would leave the model in its bind pose. If there
        // are no animation players at all (a rig with no clips, or one
        // SceneKit couldn't parse the animations of), both are `nil` and this
        // is a no-op: the model still renders, just standing still, which is
        // the fail-soft outcome the brief asks for explicitly — "a static
        // character is a bad character, a crash is a bad app."
        (idlePlayer ?? walkPlayer)?.play()
    }

    /// Where a resolved clip came from. Exists so the precedence rule can be
    /// tested as a value rather than inferred from which object identity came
    /// back — "which file won" is the thing that needs pinning.
    enum ClipSource: Equatable {
        /// From `character-idle.scn` / `character-walk.scn`.
        case dedicatedFile
        /// From the rig itself, at this index in tree-walk order.
        case embedded(Int)

        func player(fromFile file: SCNAnimationPlayer?,
                    embedded found: [(key: String, player: SCNAnimationPlayer)]) -> SCNAnimationPlayer? {
            switch self {
            case .dedicatedFile: return file
            case .embedded(let i): return found.indices.contains(i) ? found[i].player : nil
            }
        }
    }

    /// **The precedence rule, stated once.**
    ///
    /// A clip from a dedicated file **wins** over a same-role clip embedded in
    /// the rig. The reasoning: supplying `character-walk.scn` is a deliberate
    /// act, and the only reason to do it is to override whatever the rig came
    /// with. Leaving resolution order implicit would make it a coin-toss the
    /// owner cannot reason about — they would have no way to tell whether
    /// their new walk cycle was being used without watching the character.
    ///
    /// Each role resolves independently, so a rig carrying a usable Idle plus
    /// a separate `character-walk.scn` works — which is a perfectly ordinary
    /// way for a hand-over to arrive.
    ///
    /// **A role filled by a file must not also reserve an embedded clip.**
    /// The first version ran `selectClips` over the whole key list and applied
    /// precedence afterwards, so the first-found/second-found fallback handed
    /// index 0 to idle and then excluded it from walk — even when idle was
    /// already coming from a dedicated file. A rig carrying one opaquely-named
    /// clip (`"mixamo.com"`, the case this code elsewhere calls common) plus
    /// an idle file stranded that clip entirely:
    ///
    ///     resolveClips(embeddedKeys: ["mixamo.com"], hasIdleFile: true, hasWalkFile: false)
    ///       -> (idle: .dedicatedFile, walk: nil)      // the rig's only clip, unused
    ///
    /// Only roles the files have *not* filled get to claim an embedded clip,
    /// so the fallback allocates over what is actually still open. The mirror
    /// case was already correct, which is what made this an asymmetry rather
    /// than a uniform rule and easy to miss.
    ///
    /// Pure, so the rule is tested rather than inferred from a loaded file.
    static func resolveClips(embeddedKeys: [String],
                             hasIdleFile: Bool,
                             hasWalkFile: Bool) -> (idle: ClipSource?, walk: ClipSource?) {
        switch (hasIdleFile, hasWalkFile) {
        case (true, true):
            // Nothing left for the rig's clips to fill.
            return (.dedicatedFile, .dedicatedFile)

        case (true, false):
            // Only walk is open: it takes the best walk candidate from the rig
            // without idle having reserved anything first.
            return (.dedicatedFile,
                    selectSingleClip(keys: embeddedKeys, preferring: "walk", avoiding: "idle")
                        .map(ClipSource.embedded))

        case (false, true):
            return (selectSingleClip(keys: embeddedKeys, preferring: "idle", avoiding: "walk")
                        .map(ClipSource.embedded),
                    .dedicatedFile)

        case (false, false):
            let picked = selectClips(keys: embeddedKeys)
            return (picked.idle.map(ClipSource.embedded), picked.walk.map(ClipSource.embedded))
        }
    }

    /// Loads one animation out of an optional sibling clip file.
    ///
    /// Takes the **first** player in tree-walk order: a dedicated
    /// animation-only export carries exactly one clip, and first-found is
    /// deterministic if it somehow carries more. Absent is silent — that is
    /// the normal case. Present-and-unusable is logged, for the same reason
    /// the rig is: a silent fallback is indistinguishable from a drop-in
    /// nobody performed.
    private static func loadClip(named name: String, in bundle: Bundle) -> SCNAnimationPlayer? {
        guard let url = resourceURL(for: name, in: bundle) else {
            // Not there. Check whether a raw Collada clip was dropped in
            // instead, because that is a silent no-op otherwise — the same
            // trap the rig file had.
            let dae = (name as NSString).deletingPathExtension + ".dae"
            if resourceURL(for: dae, in: bundle) != nil {
                log.error("""
                    \(dae, privacy: .public) is present but iOS cannot load Collada. \
                    Convert it: xcrun scntool --convert \(dae, privacy: .public) \
                    --format scn -o \(name, privacy: .public)
                    """)
            }
            return nil
        }

        guard let scene = try? SCNScene(url: url, options: [
            .animationImportPolicy: SCNSceneSource.AnimationImportPolicy.doNotPlay
        ]) else {
            log.error("""
                \(name, privacy: .public) is present but SceneKit could not parse it; \
                ignoring it and using whatever the rig provides.
                """)
            return nil
        }

        guard let first = collectAnimationPlayers(under: scene.rootNode).first else {
            log.error("""
                \(name, privacy: .public) loaded but contains no animation. If this came \
                from Mixamo, re-download it as an animation (it does not need skin) and \
                convert it again.
                """)
            return nil
        }
        return first.player
    }

    /// The best embedded candidate for **one** role, used when the other role
    /// is already filled from a dedicated file and therefore reserves nothing.
    ///
    /// Falls back to the first clip that is not explicitly named for the other
    /// role. That last clause matters: a rig whose only clip is called "Idle",
    /// alongside a dedicated idle file, should leave walk empty rather than
    /// press an idle animation into service as a walk cycle. An opaque name
    /// like `"mixamo.com"` is fair game, because it claims nothing.
    static func selectSingleClip(keys: [String],
                                 preferring word: String,
                                 avoiding other: String) -> Int? {
        if let named = keys.firstIndex(where: { $0.localizedCaseInsensitiveContains(word) }) {
            return named
        }
        return keys.indices.first { !keys[$0].localizedCaseInsensitiveContains(other) }
    }

    /// **Which clip is idle and which is walk, decided in discovery order.**
    ///
    /// Pure, and separated from the loading so it can be tested without a
    /// rig — the animation matching was previously untestable by
    /// construction, because there is no export to load yet.
    ///
    /// The previous version asked a `Dictionary` for `keys.first { … }`.
    /// `Dictionary.keys` has **no specified order**, so a rig with two keys
    /// both containing "walk" (say `walk_forward` and `walk_back`, which is
    /// an ordinary way to name clips) picked an arbitrary one, and could pick
    /// a different one on the next launch. Matching over the array in the
    /// order the tree was walked is deterministic.
    ///
    /// Deliberately *not* a hard-coded Mixamo key: that guess cannot be
    /// tested, because the file it would guess about does not exist yet.
    static func selectClips(keys: [String]) -> (idle: Int?, walk: Int?) {
        let namedIdle = keys.firstIndex { $0.localizedCaseInsensitiveContains("idle") }
        let namedWalk = keys.firstIndex { $0.localizedCaseInsensitiveContains("walk") }

        // Fall back to first-found and second-found when the names say
        // nothing — Mixamo exports commonly come back as opaque identifiers
        // like "mixamo.com" rather than anything legible.
        let idle = namedIdle ?? keys.indices.first { $0 != namedWalk }
        let walk = namedWalk ?? keys.indices.first { $0 != idle }
        return (idle, walk)
    }

    private static func collectAnimationPlayers(
        under node: SCNNode
    ) -> [(key: String, player: SCNAnimationPlayer)] {
        var found: [(key: String, player: SCNAnimationPlayer)] = []
        func walk(_ node: SCNNode) {
            for key in node.animationKeys {
                guard let player = node.animationPlayer(forKey: key) else { continue }
                found.append((key, player))
            }
            for child in node.childNodes { walk(child) }
        }
        walk(node)
        return found
    }

    public func setMoving(_ moving: Bool) {
        guard moving != isMoving else { return }
        isMoving = moving

        // **Fewer than two distinct clips: leave whatever is playing alone.**
        // A rig carrying a single animation used to resolve idle and walk to
        // the same `SCNAnimationPlayer`, so every start and stop stopped that
        // clip and restarted it — visibly snapping the character back to
        // frame one each time the player touched or released the stick.
        // There is no second clip to cross to, so the right move is nothing.
        guard let idlePlayer, let walkPlayer, idlePlayer !== walkPlayer else { return }

        if moving {
            idlePlayer.stop()
            walkPlayer.play()
        } else {
            walkPlayer.stop()
            idlePlayer.play()
        }
    }

    public func update(distanceWalked: Double) {
        // A loaded animation clip runs on its own timeline once playing.
        // Unlike `MannequinCharacter`'s procedural gait, there is nothing
        // here to drive from distance travelled — the clip's own authored
        // timing is what the owner's Mixamo export actually looks like.
    }
}
