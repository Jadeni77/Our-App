import Foundation
import SceneKit

/// Wraps a rigged export loaded from the app bundle — the owner's Mixamo
/// character plus Idle and Walking animations, or a `.scn` recompiled from
/// it. See `CharacterLoader` for the drop-in contract this exists to serve:
/// this type exists and is fully written *before* the export itself does,
/// because that is the point of Task 3A.
public final class RiggedCharacter: Character {
    public let node: SCNNode

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

    /// `name` is a full filename (e.g. `"character.scn"`), not a bare
    /// resource name — `CharacterLoader` tries `.scn` then `.dae` and needs
    /// to say which extension it means for each attempt.
    ///
    /// Fails (returns `nil`) if the bundle has no such resource, or if
    /// SceneKit cannot parse what's there. Either way, `CharacterLoader`
    /// falls back to `MannequinCharacter` — **fail soft** (principle 7): a
    /// bad or missing export must degrade to the placeholder, never crash
    /// the app, and this initializer is the only place that can tell the
    /// difference between "not supplied yet" and "supplied but broken" —
    /// both look the same from here, which is correct, because both have
    /// the same right answer.
    public init?(sceneNamed name: String, in bundle: Bundle) {
        let filename = name as NSString
        let base = filename.deletingPathExtension
        let ext = filename.pathExtension
        guard let url = bundle.url(forResource: base, withExtension: ext) else { return nil }

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
        // than a clean container.
        let root = SCNNode()
        for child in scene.rootNode.childNodes {
            root.addChildNode(child)
        }
        self.node = root

        var byKey: [String: SCNAnimationPlayer] = [:]
        var byIndex: [SCNAnimationPlayer] = []
        Self.collectAnimationPlayers(under: root, into: &byKey, ordered: &byIndex)
        self.animationsByKey = byKey
        self.animationsByIndex = byIndex

        // Match case-insensitively against "idle"/"walk" first; fall back
        // to first/second-found by index when nothing matches (task brief).
        // This is deliberately *not* a hard-coded Mixamo key — that guess
        // cannot be tested, because the files it would guess about do not
        // exist yet.
        let idleKey = byKey.keys.first { $0.localizedCaseInsensitiveContains("idle") }
        let walkKey = byKey.keys.first { $0.localizedCaseInsensitiveContains("walk") }

        idlePlayer = idleKey.flatMap { byKey[$0] } ?? byIndex.first
        if let walkKey {
            walkPlayer = byKey[walkKey]
        } else if byIndex.count > 1 {
            walkPlayer = byIndex[1]
        } else {
            walkPlayer = byIndex.first
        }

        // Start in the idle pose. If there are no animation players at all
        // (a rig with no clips, or one SceneKit couldn't parse the
        // animations of), both are `nil` and both calls are no-ops — the
        // model still renders, just standing still, which is the fail-soft
        // outcome the brief asks for explicitly: "a static character is a
        // bad character, a crash is a bad app."
        idlePlayer?.play()
    }

    private static func collectAnimationPlayers(
        under node: SCNNode,
        into byKey: inout [String: SCNAnimationPlayer],
        ordered byIndex: inout [SCNAnimationPlayer]
    ) {
        for key in node.animationKeys {
            guard let player = node.animationPlayer(forKey: key) else { continue }
            byKey[key] = player
            byIndex.append(player)
        }
        for child in node.childNodes {
            collectAnimationPlayers(under: child, into: &byKey, ordered: &byIndex)
        }
    }

    public func setMoving(_ moving: Bool) {
        guard moving != isMoving else { return }
        isMoving = moving
        if moving {
            idlePlayer?.stop()
            walkPlayer?.play()
        } else {
            walkPlayer?.stop()
            idlePlayer?.play()
        }
    }

    public func update(distanceWalked: Double) {
        // A loaded animation clip runs on its own timeline once playing.
        // Unlike `MannequinCharacter`'s procedural gait, there is nothing
        // here to drive from distance travelled — the clip's own authored
        // timing is what the owner's Mixamo export actually looks like.
    }
}
