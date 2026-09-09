import SwiftUI
import SceneKit
import os

/// Owns the `SCNView` and the render loop.
///
/// The scene is built **once** and held. Rebuilding it on a view update is the
/// mistake that restarted Moonshot's replay from frame one on every unrelated
/// change (M51) and, in a worse form, froze the app outright (M42). A 3D scene
/// is state, not something derived from a view's body.
struct IslandSceneView: UIViewRepresentable {
    /// What the player asked to pick up, and **which thing they were
    /// looking at when they asked**.
    ///
    /// The point travels with the request rather than being looked up when
    /// the request is handled, and that is the whole reason this is a
    /// struct instead of the bare counter it started as. `ActionButton` is
    /// labelled from the offer of the frame the player *saw*; up to ~33 ms
    /// pass before the renderer acts on the tap, and `driver.step` has
    /// already recomputed `offer` from a fresher position by then. Handing
    /// the driver whatever is in reach *now* would mean a player who tapped
    /// "Eat" at a bush and drifted a step could find themselves drinking
    /// instead — an action they never chose, reported back as success. It
    /// also made `SurvivalDriver.take`'s own `offer?.id == point.id` guard
    /// (Moonshot M45: the caller is never the authority) a tautology that
    /// could not fire, which is how the bug stayed invisible.
    struct TakeRequest: Equatable, Sendable {
        /// Bumped per tap, and compared rather than watched for a rising
        /// edge, so a request is never handled twice.
        var count = 0
        /// What was in reach when the player tapped. `nil` only before the
        /// first tap of the session.
        var point: ForagePoint?

        mutating func tap(_ point: ForagePoint) {
            count += 1
            self.point = point
        }
    }

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
    /// Flows IN like `input`/`heading` rather than as a `Binding` — nothing
    /// outside this view needs to observe it change, only to cause a change.
    ///
    /// **Taps landing inside one frame deliberately coalesce into a single
    /// take.** Only the newest request is on the value the renderer reads,
    /// and it is handled once. That is the behaviour worth having: a spring
    /// is never exhausted, so letting two taps through in one frame would
    /// grant two drinks for what the player saw as one press. The counter
    /// exists to make "asked again" distinguishable from "never asked",
    /// not to queue.
    var takeRequest = TakeRequest()
    /// Ticks up when the player taps through `BlackoutView`. Flows in the
    /// same way and for the same reason as `takeRequest`, and carries no
    /// payload because there is only one thing waking can mean.
    var wakeRequest = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(terrain: terrain, survivalState: $survivalState, offer: $offer,
                    takeRequest: takeRequest, wakeRequest: wakeRequest)
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
        // Only the values that change per frame cross here, and they cross
        // together under one lock — see `Coordinator.Inbox`. The scene
        // itself is never rebuilt.
        //
        // Copied to locals first because the closure below is `@Sendable`
        // and `self` is a view value holding `Binding`s.
        let input = self.input
        let heading = self.heading
        let takeRequest = self.takeRequest
        let wakeRequest = self.wakeRequest
        context.coordinator.write {
            $0.input = input
            $0.heading = heading
            $0.take = takeRequest
            $0.wake = wakeRequest
        }
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        let scene = SCNScene()
        let camera = FollowCamera()
        let player = PlayerNode()
        private let sun = IslandLook.makeSun()
        /// A `var`, and the only mutable piece of the world here, because
        /// **replacing it is what dying costs you** — see `wake(now:)`.
        private(set) var clock = SessionClock()
        private let terrain: Terrain
        private var lastFrame: TimeInterval = 0

        let campfire: CampfireNode
        private let forageNodes: ForageNodes
        /// Not `private`: the render loop's own wiring is the one thing in
        /// this file that no pure-rule test can reach, and it is where
        /// this task's real bug lived. `IslandSceneCoordinatorTests` drives
        /// frames through this coordinator and reads the driver's answers.
        let driver: SurvivalDriver

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

        /// Everything SwiftUI writes and the render loop reads.
        ///
        /// One struct behind one lock rather than three bare properties.
        /// `updateUIView` runs on the main thread; `SCNSceneRendererDelegate`
        /// callbacks are documented **not** to necessarily run on it — so
        /// every one of these crossed threads unsynchronised. `input` is
        /// the one that can genuinely tear rather than merely arrive late:
        /// a `SIMD2<Double>` is 16 bytes and two stores, and half of an old
        /// vector beside half of a new one is a step in a direction the
        /// player never pushed. Swift 6's concurrency checking rejects all
        /// three outright, and a standalone extraction (P39) is the most
        /// likely thing to want that mode.
        struct Inbox: Sendable {
            var input: SIMD2<Double> = .zero
            var heading: Double = 0
            /// Consumed on the renderer thread rather than acted on the
            /// moment SwiftUI notices the tap, which keeps every mutation
            /// of `driver` on the one thread that already owns it —
            /// `driver.step` runs in that same callback, so taking from
            /// `updateUIView` would race the `step` call a few lines above
            /// it in this file.
            var take = TakeRequest()
            /// Bumped when the player taps through the blackout. A count
            /// rather than a flag for the same reason `TakeRequest` carries
            /// one: compared against what was last handled, so it can never
            /// be acted on twice or missed once.
            var wake = 0
        }

        private let inbox: OSAllocatedUnfairLock<Inbox>
        /// Seeded from the request the view already held at construction,
        /// not from zero: a coordinator built after the player had already
        /// tapped would otherwise read a nonzero count as a fresh request
        /// and take something on its very first frame.
        private var lastHandledTakeRequest: Int
        /// Seeded for the same reason, and the stakes are higher: an
        /// unseeded counter would wake a player who is not dead, which on
        /// the very first frame means resetting the clock of a session
        /// nobody has died in yet.
        private var lastHandledWake: Int

        func write(_ mutate: @Sendable (inout Inbox) -> Void) {
            inbox.withLock(mutate)
        }

        init(terrain: Terrain, survivalState: Binding<SurvivalState>, offer: Binding<ForagePoint?>,
             takeRequest: TakeRequest = TakeRequest(), wakeRequest: Int = 0) {
            self.terrain = terrain
            self.survivalState = survivalState
            self.offer = offer
            inbox = OSAllocatedUnfairLock(initialState: Inbox(take: takeRequest, wake: wakeRequest))
            lastHandledTakeRequest = takeRequest.count
            lastHandledWake = wakeRequest

            // Built once, here, and held for the session — same reasoning as
            // `player`/`camera` above: a scene is state, not something
            // derived from a view's body (task brief).
            let middle = Double(terrain.field.width) * terrain.definition.cellSize / 2
            let forage = ForageField.points(in: terrain,
                                            berries: ForageField.berriesPerIsland,
                                            springs: ForageField.springsPerIsland)
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

        /// You went out. You woke at the fire, at dawn.
        ///
        /// **Death costs the session, not the island (F3), and the clock is
        /// where that cost is actually charged.** The other two lines here
        /// give something back — `revive` fills the needs, and the player
        /// is put somewhere safe — so without the third, dying would be
        /// free, or better than free at the end of a bad night. Replacing
        /// the clock is what takes something: the island is exactly as you
        /// left it, every bush you picked is still picked, nothing built is
        /// lost, and the day you were most of the way through is gone.
        ///
        /// It is also the reason the clock could stay session-scoped in the
        /// first place. Persistent decay was rejected because a partner's
        /// busy week must not be damage to your island; the flip side is
        /// that a survival loop needs *something* real to lose, and a
        /// session is the only thing here that is yours alone to lose.
        ///
        /// Takes `now` rather than reading the clock itself so the promise
        /// — that the moment you wake reads as dawn — is exactly, not
        /// approximately, testable.
        func wake(now: Date) {
            driver.revive()
            player.place(x: campfire.worldX, z: campfire.worldZ, on: terrain)
            clock = SessionClock(startedAt: now)
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            // One read, one lock acquisition, one snapshot for the whole
            // frame. Reading the properties one at a time would let the
            // main thread land a tap between two of them, so the player
            // could walk on this frame's input toward last frame's offer.
            let inbox = self.inbox.withLock { $0 }

            // Before anything else this frame. Waking moves the player and
            // replaces the clock, and every line below wants to run against
            // where they actually are and what time it actually is.
            if inbox.wake != lastHandledWake {
                lastHandledWake = inbox.wake
                wake(now: Date())
            }

            // First frame has no previous timestamp; a dt of `time` itself
            // would teleport the player across the island on frame one.
            let dt = lastFrame == 0 ? 0 : min(time - lastFrame, 0.1)
            lastFrame = time

            player.step(input: inbox.input, heading: inbox.heading, dt: dt, terrain: terrain)
            camera.follow(player, heading: inbox.heading)

            let now = Date()
            let isNight = clock.isNight(at: now)
            driver.step(playerX: player.worldX, playerZ: player.worldZ,
                       playerHeight: terrain.height(atX: player.worldX, z: player.worldZ),
                       dt: dt, isNight: isNight, now: now)

            // `!=`, not "became true": a counter that ticked twice between
            // two frames must still only be handled once here, and `take`
            // itself is what decides whether it succeeds — this only asks.
            //
            // The point comes from the REQUEST, never from `driver.offer`,
            // which `step` above has already recomputed from this frame's
            // position. Asking for what the player tapped is what lets
            // `take` refuse when they have since walked off it, instead of
            // silently substituting whatever is in reach now.
            if inbox.take.count != lastHandledTakeRequest {
                lastHandledTakeRequest = inbox.take.count
                if let tapped = inbox.take.point {
                    driver.take(tapped, now: now)
                }
            }

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
