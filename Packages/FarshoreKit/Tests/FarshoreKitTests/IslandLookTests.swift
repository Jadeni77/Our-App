import Foundation
import SceneKit
import Testing
import UIKit
@testable import FarshoreKit

/// The look is mostly art, but the parts that are *settings* are cheap to pin
/// and expensive to lose — a physically-based material silently missing its
/// normal map looks merely "a bit flat", which nobody files a bug about.
struct IslandLookTests {
    @Test func theGroundIsPhysicallyBasedAndFullyMapped() {
        let material = IslandLook.groundMaterial(in: .module)
        #expect(material.lightingModel == .physicallyBased)
        #expect(material.diffuse.contents != nil)
        #expect(material.normal.contents != nil)
        #expect(material.roughness.contents != nil)
        #expect(material.ambientOcclusion.contents != nil)
    }

    /// Tiling is what stops a 1 m texture stretching across a 512 m island.
    @Test func theGroundTilesRatherThanStretches() {
        let material = IslandLook.groundMaterial(in: .module)
        #expect(material.diffuse.wrapS == .repeat)
        #expect(material.diffuse.wrapT == .repeat)
    }

    /// The single biggest realism lever in the whole table (spec §4), and free.
    ///
    /// Two assets, not one: Task 0's spike found that a raw `.hdr` lights
    /// nothing (`scene.lightingEnvironment.contents` from it renders the whole
    /// island black under `camera.wantsHDR`), while the same file is a
    /// perfectly good `background`.
    ///
    /// **The assertion is about the type, and it has to be.** `contents != nil`
    /// — what this asserted until the final branch review — passes for the
    /// exact bug it was written to catch: pointing `lightingEnvironment` at
    /// the raw `sky.hdr` gives it a non-nil `URL`, all 41 tests stay green,
    /// and the island renders black on a device. Verified by reintroducing it.
    /// What actually distinguishes the working configuration from the broken
    /// one is *which container* each property holds: the environment must be
    /// the tone-mapped 8-bit `UIImage` (`sky_env.png`), the background must be
    /// the Radiance `URL` (`sky.hdr`). So assert exactly that.
    @Test func theSceneGetsAnImageBasedLightingEnvironment() {
        let scene = SCNScene()
        IslandLook.configure(scene: scene, bundle: .module)
        #expect(scene.lightingEnvironment.contents is UIImage)
        #expect(scene.background.contents is URL)
        // Tolerance, not pedantry: `intensity` is a `CGFloat` in the API and a
        // `Float` in SceneKit's storage, so anything but an exactly
        // representable value reads back changed.
        #expect(abs(scene.lightingEnvironment.intensity - IslandLook.dayEnvironmentIntensity) < 0.000_01)
    }

    /// `SkyController.apply` has to put the daylight sky back after night, so
    /// there is exactly one place that decides what the daylight sky *is*.
    /// If `configure` ever stops going through it, dawn restores a different
    /// sky from the one the session opened with.
    @Test func theDaySkyIsSingleSourced() {
        let scene = SCNScene()
        IslandLook.configure(scene: scene, bundle: .module)
        #expect(scene.background.contents as? URL == IslandLook.daySkyBackground(in: .module) as? URL)
    }

    /// Fog is a look decision, so this file owns the number and
    /// `SkyController.apply` references it. Pinned here because `apply`
    /// overwrites `fogColor` every tick: without this, a literal creeping back
    /// into `SkyController` would make retuning the fog here a no-op.
    @Test func daylightFogComesFromTheNamedConstant() {
        let scene = SCNScene()
        IslandLook.configure(scene: scene, bundle: .module)
        #expect(scene.fogColor as? UIColor == IslandLook.dayFogColor)
    }

    @Test func theCameraRendersWithFilmicPost() {
        let camera = SCNCamera()
        IslandLook.configure(camera: camera)
        #expect(camera.wantsHDR)
        #expect(camera.wantsDepthOfField)
        #expect(camera.bloomIntensity > 0)
    }

    /// **Auto-exposure and the night cycle are in direct opposition**, so the
    /// clamp is the only thing keeping both. Adaptation's whole job is to
    /// cancel global luminance changes; `SkyController.apply` makes night by
    /// dropping `lightingEnvironment.intensity` 1.0 → 0.12, about three stops,
    /// which unclamped adaptation would spend a second or two undoing. The
    /// spike hit the mirror-image failure on device: metering the HDRI's sun
    /// disk drove exposure down until the ground was black.
    ///
    /// SceneKit's defaults are ±15 stops, i.e. effectively unbounded, and
    /// `wantsExposureAdaptation` is `true` out of the box — both measured, not
    /// assumed. So "somebody deleted the clamp" and "somebody never set it"
    /// look identical from here, which is why this asserts the actual bound
    /// rather than merely that some bound exists.
    @Test func exposureAdaptationIsClampedSoItCannotUndoNightfall() {
        let camera = SCNCamera()
        IslandLook.configure(camera: camera)
        #expect(camera.wantsExposureAdaptation)
        #expect(camera.minimumExposure == -IslandLook.exposureAdaptationLimit)
        #expect(camera.maximumExposure == IslandLook.exposureAdaptationLimit)
        // Night is ~3 stops. The clamp must stay well inside that or it can
        // still swallow the feature it was added to protect.
        #expect(IslandLook.exposureAdaptationLimit < 1.5)
    }
}
