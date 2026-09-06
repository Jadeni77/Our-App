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

    /// The sky the player *sees* by day: the raw Radiance `.hdr`, as a URL.
    ///
    /// Declared as a function rather than inlined into `configure` because
    /// `SkyController.apply` has to put it *back* after night, and the day sky
    /// is exactly the class of decision this file exists to hold. Resolving
    /// the URL is the caller's job to do once and hold: `apply` runs every
    /// frame and re-decoding a 4.6 MB Radiance image at 30 Hz would cost more
    /// than the rest of the render loop combined.
    ///
    /// Returns `Any?` rather than `URL?` because that is what
    /// `SCNMaterialProperty.contents` takes, and the night sky it alternates
    /// with is a `UIColor` — keeping one type across both ends of the swap
    /// avoids an optional-into-`Any` conversion at the assignment, where a
    /// double-wrapped optional would show up as a sky that silently fails to
    /// load rather than as a compile error.
    public static func daySkyBackground(in bundle: Bundle) -> Any? {
        bundle.url(forResource: "sky", withExtension: "hdr")
    }

    /// The sky at night. **A flat colour on purpose.** Slice 1's job is a
    /// walkable island, not a shipping sky; a second HDRI would be a second
    /// 4.6 MB asset and a second thing to keep provenance-consistent (spec §4)
    /// for a state the player sees for 5.6 minutes of a 20-minute cycle. A
    /// near-black blue reads as night the moment the fog and the environment
    /// dim to match, and swapping it for a real night HDRI later is a one-line
    /// change to this constant.
    public static let nightSkyColor = UIColor(red: 0.02, green: 0.03, blue: 0.06, alpha: 1)

    /// Daylight fog. Haze at distance is most of what makes a 512 m island
    /// read as *large* rather than as a small model close up.
    ///
    /// Declared here and referenced by `SkyController.apply`, which overwrites
    /// `scene.fogColor` on every tick: a second literal there would mean
    /// retuning the fog in this file — the file whose stated job is holding
    /// these decisions — silently reverting on the very next frame. This is
    /// the same defect that `textureScale`, `sunPeakIntensity` and
    /// `duskFraction` were each fixed for on this branch.
    ///
    /// **Trap for a future tidy-up: the `0.72` here is not the other `0.72`.**
    /// `SessionClock.duskFraction` is also 0.72, `SkyController.apply` reads it
    /// two lines above where it used to write this grey, and the two numbers
    /// are unrelated — one is a fraction of a day, the other is a grey level.
    /// They agree by coincidence. Do not single-source them together.
    public static let dayFogColor = UIColor(white: 0.72, alpha: 1)

    /// Night fog: dark enough to close the world in, light enough that the
    /// silhouette of the terrain still separates from the sky.
    public static let nightFogColor = UIColor(white: 0.10, alpha: 1)

    /// Full strength for the image-based lighting — the single biggest realism
    /// lever in the spec's §4 table, so daylight runs it at 1:1. Same
    /// single-sourcing reason as `dayFogColor`: `SkyController.apply`
    /// overwrites `lightingEnvironment.intensity` every tick.
    public static let dayEnvironmentIntensity: CGFloat = 1.0

    /// Night is lit by the environment alone, dimmed to roughly three stops
    /// below noon — which is what makes fire matter in slice 2 without
    /// anything in slice 1 knowing that fire is coming.
    public static let nightEnvironmentIntensity: CGFloat = 0.12

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
        scene.background.contents = daySkyBackground(in: bundle)
        if let environment = image(named: "sky_env", extension: "png", in: bundle) {
            scene.lightingEnvironment.contents = environment
            scene.lightingEnvironment.intensity = dayEnvironmentIntensity
        }
        scene.fogColor = dayFogColor
        scene.fogStartDistance = 60
        scene.fogEndDistance = 420
        scene.fogDensityExponent = 2
    }

    /// How far auto-exposure may drift, in stops. See `configure(camera:)`.
    public static let exposureAdaptationLimit: CGFloat = 0.5

    public static func configure(camera: SCNCamera) {
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = true
        // **Clamped, and it must stay clamped.** Auto-exposure exists to cancel
        // global luminance changes, and the day/night cycle *is* a global
        // luminance change: `SkyController.apply` makes night by dropping
        // `lightingEnvironment.intensity` from 1.0 to 0.12 — about three stops
        // — which is precisely the signal an unclamped adaptation would spend
        // the next second or two undoing, drifting night back toward mid-grey
        // and quietly deleting the feature.
        //
        // The same clamp fixes the opposite failure the task 0 spike hit on
        // device: outdoors, SceneKit meters the HDRI's *sun disk* and drives
        // exposure down until the ground is black and the sky is blown. The
        // spike's own conclusion was to switch adaptation off and use a fixed
        // exposure per time of day. Bounding it is the smaller change and
        // keeps what adaptation is actually good for here — a gentle settle
        // when the player turns from the sun into a shadowed slope — while
        // making both runaway directions impossible. Half a stop each way is
        // a factor of ~1.41 in either direction; nightfall is ~8.
        //
        // **Deleting the line above would not have worked**, which is the
        // reason this is a clamp rather than a switch-off:
        // `wantsExposureAdaptation` defaults to `true` on `SCNCamera`, and
        // `minimumExposure`/`maximumExposure` default to −15 and +15 stops,
        // i.e. effectively unbounded. Adaptation is something you opt *out*
        // of, and nothing here was opting out. Measured, not assumed.
        //
        // If night ever looks washed out again, check this before retuning
        // `nightEnvironmentIntensity`: a wider clamp will silently eat the
        // retune too.
        camera.minimumExposure = -exposureAdaptationLimit
        camera.maximumExposure = exposureAdaptationLimit
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
