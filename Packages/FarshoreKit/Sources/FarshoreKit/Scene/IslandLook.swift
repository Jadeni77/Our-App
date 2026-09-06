import Foundation
import SceneKit
import UIKit

/// Everything that decides how the island *looks*, in one place.
///
/// The module owns its own visual identity (P39) — it cannot reach the app's
/// theme and must not try. A daylit wilderness island has no business
/// inheriting the moonlit couples palette anyway.
///
/// Ordered by the spec's §4 table: the free levers first. Image-based lighting
/// and scan-quality PBR maps are the two biggest contributors to realism here
/// and neither costs anything, which is why they are load-bearing rather than
/// polish.
public enum IslandLook {
    /// `UIImage(named:in:with:)` silently assumes **`.png`** for any name given
    /// without an extension — a long-standing UIKit quirk, not a bug in this
    /// package. That is invisible for `sky_env.png` and fatal for the ground
    /// maps: `UIImage(named: "ground_color", in: bundle, with: nil)` returns
    /// `nil` for a `.jpg`, silently, with no error to grep for. Resolving the
    /// URL first (the same pattern `HeightFieldLoader` already uses) sidesteps
    /// the guess entirely.
    private static func image(named name: String, extension ext: String, in bundle: Bundle) -> UIImage? {
        guard let url = bundle.url(forResource: name, withExtension: ext) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// This material applies **no tiling of its own** — no
    /// `contentsTransform`, no scale. The repeat rate the ground actually
    /// shows comes entirely from `TerrainMeshBuilder.textureScale`, baked into
    /// the mesh's UVs when each chunk is built. The two are one decision
    /// split across two files on purpose (`TerrainMeshBuilder` is the single
    /// declaration of the number); if you retune the tiling, that constant is
    /// the only place to touch, and this comment is how the next reader finds
    /// it from here.
    public static func groundMaterial(in bundle: Bundle) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = image(named: "ground_color", extension: "jpg", in: bundle)
        material.normal.contents = image(named: "ground_normal", extension: "jpg", in: bundle)
        material.roughness.contents = image(named: "ground_roughness", extension: "jpg", in: bundle)
        material.ambientOcclusion.contents = image(named: "ground_ao", extension: "jpg", in: bundle)
        for property in [material.diffuse, material.normal,
                         material.roughness, material.ambientOcclusion] {
            property.wrapS = .repeat
            property.wrapT = .repeat
            property.mipFilter = .linear
            // Grazing angles are most of what you see on a landscape; without
            // this the ground turns to mush a few metres ahead of the player.
            property.maxAnisotropy = 8
        }
        return material
    }

    public static func configure(scene: SCNScene, bundle: Bundle) {
        // Two *different* images, not one shared between both properties —
        // this split is load-bearing, not a stylistic choice, so read this
        // before "simplifying" it back to one file.
        //
        // Task 0's spike measured that iOS accepts a raw Radiance `.hdr` for
        // *both* `scene.background.contents` and
        // `scene.lightingEnvironment.contents` — ImageIO reads it fine either
        // way, and the sky renders correctly from it. But with
        // `camera.wantsHDR = true` (which the filmic post below turns on),
        // using that same `.hdr` as the lighting environment lights nothing:
        // ground luminance measured 0.0-0.5 out of 255 at every exposure
        // offset tried, and neither `whitePoint`, `averageGray`, exposure
        // adaptation, nor raising `lightingEnvironment.intensity` rescued it.
        // An 8-bit tone-mapped equirectangular copy of the identical sky
        // measured 185.7. So the sky the player *sees* is the HDR original,
        // and the sky that *lights the island* is the tone-mapped copy —
        // same picture, two files, because only one of them works as IBL
        // input under `wantsHDR`. See task-0-report.md, "The .hdr answer".
        if let skyURL = bundle.url(forResource: "sky", withExtension: "hdr") {
            scene.background.contents = skyURL
        }
        if let environment = image(named: "sky_env", extension: "png", in: bundle) {
            scene.lightingEnvironment.contents = environment
            scene.lightingEnvironment.intensity = 1.0
        }
        scene.fogColor = UIColor(white: 0.72, alpha: 1)
        scene.fogStartDistance = 60
        scene.fogEndDistance = 420
        scene.fogDensityExponent = 2
    }

    public static func configure(camera: SCNCamera) {
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = true
        camera.wantsDepthOfField = true
        camera.focusDistance = 12
        camera.fStop = 8
        camera.bloomIntensity = 0.25
        camera.bloomThreshold = 0.75
        camera.motionBlurIntensity = 0.4
        camera.zFar = 600
        camera.zNear = 0.1
    }

    /// The sun's brightness at high noon. Declared exactly once: `makeSun()`
    /// uses it as the light's initial intensity, and `SkyController.apply`
    /// (Task 5) uses it as the ceiling of the day/night curve, because that
    /// function overwrites `light.intensity` on every tick. A second literal
    /// here would mean retuning `makeSun()` does nothing — the next tick
    /// silently reverts it to whatever `SkyController` still thinks noon is.
    /// If you retune the sun's brightness, this is the only constant to touch.
    public static let sunPeakIntensity: CGFloat = 2_400

    /// A low, warm key light. `castsShadow` is what makes the terrain read as
    /// having form at all — an unshadowed heightmap looks painted on.
    public static func makeSun() -> SCNNode {
        let light = SCNLight()
        light.type = .directional
        light.intensity = sunPeakIntensity
        light.color = UIColor(red: 1.0, green: 0.94, blue: 0.86, alpha: 1)
        light.castsShadow = true
        light.shadowMode = .deferred
        light.shadowSampleCount = 8
        light.shadowRadius = 3
        light.maximumShadowDistance = 140
        light.orthographicScale = 60
        let node = SCNNode()
        node.light = light
        return node
    }
}
