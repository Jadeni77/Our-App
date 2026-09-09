import Foundation
import SceneKit
import UIKit

/// The one heat source on the island, built entirely from SceneKit
/// primitives — a stone ring and a cone of logs — no downloaded asset, same
/// reasoning as `MannequinCharacter` (principle 3).
///
/// **No tests here.** This is rendering, and this project has learned
/// (`task-4-brief.md`) that asserting on a SceneKit node tree pins the
/// implementation rather than the behaviour it expresses — the behaviour
/// (what "near the fire" means, how much it warms you) is already pinned by
/// `ProximityRulesTests` and `SurvivalRulesTests`. What this file adds is a
/// picture of a fact those tests already established, and the one thing
/// worth guarding — that the picture agrees with the fact — is guarded by
/// referencing the constant below rather than restating it.
public final class CampfireNode: SCNNode {
    public private(set) var worldX: Double
    public private(set) var worldZ: Double

    /// Firelight above the flame source, not at ground level, so the glow
    /// visibly comes from something burning rather than from the dirt.
    private static let flameHeight: Float = 0.35

    /// By day the sun (`IslandLook.sunPeakIntensity`, 2,400) dwarfs any fire,
    /// so this only has to be non-zero — enough that the fire reads as *lit*
    /// in a screenshot taken at noon, not enough to fight the sun for
    /// attention.
    private static let dayIntensity: CGFloat = 150
    /// After dark the environment alone lights the island at roughly three
    /// stops below noon (`IslandLook.nightEnvironmentIntensity`), which is
    /// the entire reason a fire is worth building: this is what actually
    /// separates "warm and lit" from "cold and dark" once the sun is gone.
    /// `setNight` is what switches between the two — a fire that looked
    /// identical at noon and midnight would tell the player nothing had
    /// changed about standing near it.
    private static let nightIntensity: CGFloat = 1_100

    private static let ringRadius: CGFloat = 0.55
    private static let ringPipeRadius: CGFloat = 0.09
    private static let logsBottomRadius: CGFloat = 0.32
    private static let logsTopRadius: CGFloat = 0.04
    private static let logsHeight: CGFloat = 0.5

    private let fireLightNode = SCNNode()

    public init(x: Double, z: Double, on terrain: Terrain) {
        worldX = x
        worldZ = z
        super.init()
        position = SCNVector3(Float(x), Float(terrain.height(atX: x, z: z)), Float(z))

        addChildNode(Self.makeRing())
        addChildNode(Self.makeLogs())

        let light = SCNLight()
        light.type = .omni
        // A warm orange, the colour flame actually reads as at this
        // saturation — a white or yellow omni here would look like a lamp,
        // not a fire.
        light.color = UIColor(red: 1.0, green: 0.52, blue: 0.18, alpha: 1)
        light.intensity = Self.dayIntensity
        light.castsShadow = true

        // **Referenced, never restated.** `ProximityRules.fireWarmthRadius`
        // is the boundary between "the fire keeps you alive" and "it does
        // not" — a pure fact with no rendering in it at all. Pointing the
        // light's own falloff at that same constant is what makes the glow a
        // true statement about the survival rules rather than an
        // independent artistic guess that happens to roughly agree today.
        // "One decision written as two literals in two files" has already
        // been found and fixed five times on this branch (see
        // `IslandLook`'s comments on `textureScale`, `sunPeakIntensity`,
        // `duskFraction` and `dayFogColor`); a literal radius here would make
        // it six, and this one is worse than cosmetic — it would let the
        // player SEE a warm-looking glow standing somewhere the rules
        // consider cold.
        light.attenuationStartDistance = 0
        light.attenuationEndDistance = ProximityRules.fireWarmthRadius

        fireLightNode.light = light
        fireLightNode.position = SCNVector3(0, Self.flameHeight, 0)
        addChildNode(fireLightNode)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Raises the fire's light after dark. See the doc comment on
    /// `nightIntensity` for why this exists at all rather than a single
    /// fixed brightness.
    public func setNight(_ isNight: Bool) {
        fireLightNode.light?.intensity = isNight ? Self.nightIntensity : Self.dayIntensity
        // **Shadows only after dark.** An `.omni` caster needs an
        // omnidirectional shadow map — a materially different cost from the
        // sun's single deferred directional one next door in `IslandLook` —
        // and by day this light runs at 150 against a sun at 2400, so it
        // was paying for a map that contributes almost nothing for 72% of
        // the cycle. F12's headroom (p95 17.20 ms of a 33.3 ms budget) was
        // measured with no props and one caster, and the owner's device is
        // off-limits, so the honest move is to not spend budget nobody has
        // re-measured.
        fireLightNode.light?.castsShadow = isNight
    }

    /// A low stone ring the logs sit inside — reads as a fire pit even before
    /// anything is burning in it.
    private static func makeRing() -> SCNNode {
        let torus = SCNTorus(ringRadius: ringRadius, pipeRadius: ringPipeRadius)
        torus.firstMaterial = material(color: UIColor(white: 0.42, alpha: 1), roughness: 0.9)
        let node = SCNNode(geometry: torus)
        node.position = SCNVector3(0, Float(ringPipeRadius), 0)
        return node
    }

    /// A single cone standing in for a stacked bundle of logs — a teepee
    /// silhouette is the recognisable shorthand for "campfire" at the
    /// distance the player actually sees this from, and matches the brief's
    /// ask for "a small cone of logs" rather than individually modelled logs.
    private static func makeLogs() -> SCNNode {
        let cone = SCNCone(topRadius: logsTopRadius, bottomRadius: logsBottomRadius, height: logsHeight)
        cone.firstMaterial = material(color: UIColor(red: 0.32, green: 0.20, blue: 0.11, alpha: 1), roughness: 0.85)
        let node = SCNNode(geometry: cone)
        node.position = SCNVector3(0, Float(logsHeight / 2), 0)
        return node
    }

    /// Same PBR lighting model as the ground and the mannequin — **not a
    /// second material style** (task brief). A fire built with unlit or
    /// Blinn-Phong materials would sit in the scene like it had been
    /// composited from a different renderer.
    private static func material(color: UIColor, roughness: Double) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        material.roughness.contents = roughness
        return material
    }
}
