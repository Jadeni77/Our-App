import Foundation
import SceneKit
import Testing
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
    /// perfectly good `background`. So this asserts both halves independently
    /// — losing either one is a real regression, not a rounding error.
    @Test func theSceneGetsAnImageBasedLightingEnvironment() {
        let scene = SCNScene()
        IslandLook.configure(scene: scene, bundle: .module)
        #expect(scene.lightingEnvironment.contents != nil)
        #expect(scene.background.contents != nil)
    }

    @Test func theCameraRendersWithFilmicPost() {
        let camera = SCNCamera()
        IslandLook.configure(camera: camera)
        #expect(camera.wantsHDR)
        #expect(camera.wantsDepthOfField)
        #expect(camera.bloomIntensity > 0)
    }
}
