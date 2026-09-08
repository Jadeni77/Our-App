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
    /// Pushed OUT of the coordinator every frame, the opposite direction
    /// from `input`/`heading` — see `Coordinator.renderer(_:updateAtTime:)`.
    /// Task 6's `NeedsFeedback` and `ActionButton` are the reason these
    /// exist: both are driven by what the survival driver decided this
    /// frame, and neither lives inside this view's own hierarchy.
    @Binding var survivalState: SurvivalState
    @Binding var offer: ForagePoint?

    func makeCoordinator() -> Coordinator {
        Coordinator(terrain: terrain, survivalState: $survivalState, offer: $offer)
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

        private let campfire: CampfireNode
        private let forageNodes: ForageNodes
        private let driver: SurvivalDriver

        /// The bindings `state`/`offer` are pushed into. Stored as
        /// `Binding`, not as a reference back to the `IslandSceneView`
        /// value itself: `IslandSceneView` is a struct, so holding one
        /// would only capture whatever `input`/`heading` were at
        /// `makeCoordinator` time, never a later one. A `Binding` reads and
        /// writes through to the SwiftUI storage that is actually live.
        private let survivalState: Binding<SurvivalState>
        private let offer: Binding<ForagePoint?>

        /// Resolved once and held for the session. `SkyController.apply` needs
        /// the daylight sky to put back at dawn, and it runs every frame — a
        /// bundle lookup per frame for a value that cannot change is the kind
        /// of cost that never shows up as a bug, only as a worse frame time.
        private let daySky = IslandLook.daySkyBackground(in: .module)

        var input: SIMD2<Double> = .zero
        var heading: Double = 0

        init(terrain: Terrain, survivalState: Binding<SurvivalState>, offer: Binding<ForagePoint?>) {
            self.terrain = terrain
            self.survivalState = survivalState
            self.offer = offer

            // Built once, here, and held for the session — same reasoning as
            // `player`/`camera` above: a scene is state, not something
            // derived from a view's body (task brief).
            let middle = Double(terrain.field.width) * terrain.definition.cellSize / 2
            let forage = ForageField.points(in: terrain, berries: 40, springs: 6)
            campfire = CampfireNode(x: middle, z: middle, on: terrain)
            forageNodes = ForageNodes(points: forage, on: terrain)
            driver = SurvivalDriver(fire: (x: middle, z: middle), points: forage,
                                    seaLevel: terrain.definition.seaLevel)

            super.init()
            IslandLook.configure(scene: scene, bundle: .module)
            scene.rootNode.addChildNode(TerrainNode(terrain: terrain,
                                                    material: IslandLook.groundMaterial(in: .module)))
            scene.rootNode.addChildNode(sun)
            scene.rootNode.addChildNode(campfire)
            scene.rootNode.addChildNode(forageNodes)
            player.attach(CharacterLoader.make(in: .module))
            scene.rootNode.addChildNode(player)
            scene.rootNode.addChildNode(camera)

            // The campfire sits at the island centre and so does the player
            // (task brief) — you start the session at your own camp.
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

            let now = Date()
            let isNight = clock.isNight(at: now)
            driver.step(playerX: player.worldX, playerZ: player.worldZ,
                       playerHeight: terrain.height(atX: player.worldX, z: player.worldZ),
                       dt: dt, isNight: isNight, now: now)
            campfire.setNight(isNight)
            SkyController.apply(timeOfDay: clock.timeOfDay(at: now),
                                sun: sun, scene: scene, daySky: daySky)

            // Pushed out on the main thread, deliberately: `updateAtTime` is
            // documented to run on SceneKit's own rendering thread, not
            // necessarily the main thread, and mutating SwiftUI-owned state
            // off the main thread is undefined behaviour there even when it
            // happens not to crash. `async` rather than `sync` because this
            // callback cannot afford to block on the main run loop scheduling
            // it back in — the next frame is due in 1/30 s regardless.
            let state = driver.state
            let currentOffer = driver.offer
            DispatchQueue.main.async { [survivalState, offer] in
                survivalState.wrappedValue = state
                offer.wrappedValue = currentOffer
            }
        }
    }
}
