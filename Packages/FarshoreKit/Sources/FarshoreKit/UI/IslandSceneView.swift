import SwiftUI
import SceneKit

/// Owns the `SCNView` and the render loop.
///
/// The scene is built **once** and held. Rebuilding it on a view update is the
/// mistake that restarted Moonshot's replay from frame one on every unrelated
/// change (M51) and, in a worse form, froze the app outright (M42). A 3D scene
/// is state, not something derived from a view's body.
struct IslandSceneView: UIViewRepresentable {
    let terrain: Terrain
    @Binding var input: SIMD2<Double>
    @Binding var heading: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(terrain: terrain)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.camera
        view.delegate = context.coordinator
        view.rendersContinuously = true
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 30      // F8 — a stable 30 beats an unstable 60
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        // Only the two values that change per frame cross here. The scene
        // itself is never rebuilt.
        context.coordinator.input = input
        context.coordinator.heading = heading
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        let scene = SCNScene()
        let camera = FollowCamera()
        let player = PlayerNode()
        private let sun = IslandLook.makeSun()
        private let clock = SessionClock()
        private let terrain: Terrain
        private var lastFrame: TimeInterval = 0

        var input: SIMD2<Double> = .zero
        var heading: Double = 0

        init(terrain: Terrain) {
            self.terrain = terrain
            super.init()
            IslandLook.configure(scene: scene, bundle: .module)
            scene.rootNode.addChildNode(TerrainNode(terrain: terrain,
                                                    material: IslandLook.groundMaterial(in: .module)))
            scene.rootNode.addChildNode(sun)
            scene.rootNode.addChildNode(player)
            scene.rootNode.addChildNode(camera)

            let middle = Double(terrain.field.width) * terrain.definition.cellSize / 2
            player.place(x: middle, z: middle, on: terrain)
            camera.follow(player, heading: 0)
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            // First frame has no previous timestamp; a dt of `time` itself
            // would teleport the player across the island on frame one.
            let dt = lastFrame == 0 ? 0 : min(time - lastFrame, 0.1)
            lastFrame = time

            player.step(input: input, heading: heading, dt: dt, terrain: terrain)
            camera.follow(player, heading: heading)
            SkyController.apply(timeOfDay: clock.timeOfDay(at: Date()),
                                sun: sun, scene: scene)
        }
    }
}
