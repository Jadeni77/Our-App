import Foundation
import SceneKit
import SwiftUI
import Testing
@testable import FarshoreKit

/// The render loop's own wiring, driven frame by frame.
///
/// Everything the coordinator *decides* is already pinned one layer down —
/// `SurvivalRules`, `ProximityRules`, `ForageField` and `SurvivalDriver` all
/// have their own suites. What lives only here is what the coordinator
/// *asks*: which values it hands the rules, and which frame's answer it
/// hands back. That gap is not academic. It is where this task's real bug
/// was, and it survived a full review of the driver — because the driver was
/// correct, and the caller was defeating it.
///
/// A real `SCNRenderer` is passed to `renderer(_:updateAtTime:)` only because
/// the signature demands an `SCNSceneRenderer`; nothing under test reads it,
/// and nothing is ever drawn.
///
/// `@MainActor` for the same reason `PlayerNodeStepFacingTests` is: the test
/// target builds in Swift 6 language mode, scene-graph objects are not
/// `Sendable`, and scene work belongs on the main actor anyway.
@MainActor
struct IslandSceneCoordinatorTests {
    private func island() throws -> Terrain {
        Terrain(field: try HeightFieldLoader.load(.farshore01, from: .module),
                definition: .farshore01)
    }

    /// The bindings exist for SwiftUI's benefit and are written from a
    /// `DispatchQueue.main.async` the coordinator schedules. These tests
    /// assert against the driver directly rather than against what lands in
    /// SwiftUI a run loop later, so constant bindings that swallow the
    /// writes are exactly right here — the push-out path is not what is
    /// under test.
    private func makeCoordinator(_ terrain: Terrain) -> IslandSceneView.Coordinator {
        IslandSceneView.Coordinator(terrain: terrain,
                                    survivalState: .constant(.rested),
                                    offer: .constant(nil))
    }

    private func frames() -> SCNRenderer {
        SCNRenderer(device: nil, options: nil)
    }

    /// A request as `ActionButton` would build one. Returned as a value
    /// rather than mutated in place at the call site because
    /// `Coordinator.write` takes a `@Sendable` closure, which cannot
    /// capture a `var`.
    private func tap(_ point: ForagePoint) -> IslandSceneView.TakeRequest {
        var request = IslandSceneView.TakeRequest()
        request.tap(point)
        return request
    }

    /// The island's own forage, derived by the same call the coordinator
    /// makes — so these are the very points it holds. That this works at
    /// all is F2: the field is a pure function of the terrain, so a test
    /// can recompute it instead of being handed it.
    private func forage(on terrain: Terrain) -> [ForagePoint] {
        ForageField.points(in: terrain,
                           berries: ForageField.berriesPerIsland,
                           springs: ForageField.springsPerIsland)
    }

    /// **The bug this file was written for.**
    ///
    /// `ActionButton` is labelled from the offer of the frame the player
    /// SAW, and up to ~33 ms pass before the render loop acts on the tap —
    /// by which time `driver.step` has already recomputed `offer` from a
    /// fresher position. A take that reads `driver.offer` instead of the
    /// point that was tapped therefore substitutes whatever is in reach
    /// *now*: tap "Drink" at a spring, drift onto a bush, and you eat
    /// instead, and are told it worked. It also made
    /// `SurvivalDriver.take`'s `offer?.id == point.id` guard — the Moonshot
    /// M45 rule that the caller is never the authority — a tautology that
    /// could never fire, which is how it stayed invisible through a review
    /// of the driver itself.
    ///
    /// The assertion is `pickedAt`, not a need's value, deliberately: needs
    /// are clamped at 1 and dt is capped at 0.1 s per frame, so a wrongly
    /// granted drink or meal can be entirely absorbed by the clamp and
    /// prove nothing. A bush that was picked leaves a timestamp that
    /// nothing can absorb.
    @Test func tappingTakesTheTappedPointAndNotWhateverIsInReachNow() throws {
        let terrain = try island()
        let coordinator = makeCoordinator(terrain)
        let renderer = frames()

        let points = forage(on: terrain)
        let spring = try #require(points.first { $0.kind == .spring })
        let bush = try #require(points.first { $0.kind == .berries })

        // Frame one: standing at the spring, so "Drink" is what the button
        // offers and what the player presses.
        coordinator.player.place(x: spring.x, z: spring.z, on: terrain)
        coordinator.renderer(renderer, updateAtTime: 1)
        #expect(coordinator.driver.offer?.id == spring.id)

        let request = tap(spring)
        coordinator.write { $0.take = request }

        // …and then they drift onto a bush before the next frame is drawn.
        coordinator.player.place(x: bush.x, z: bush.z, on: terrain)
        coordinator.renderer(renderer, updateAtTime: 2)

        // The bush really was in reach, so the take had something to
        // wrongly substitute — without this the test could pass for the
        // uninteresting reason that nothing was reachable at all.
        #expect(coordinator.driver.offer?.id == bush.id)

        // And it was not picked. The player asked for the spring; the
        // spring is gone; nothing happens.
        #expect(coordinator.driver.pickedAt.isEmpty)
    }

    /// The other half of the same wiring: when the player has NOT moved,
    /// the tap must still go through. A "fix" that simply stopped taking
    /// anything would pass the test above and fail this one.
    @Test func tappingWhatIsStillInReachTakesIt() throws {
        let terrain = try island()
        let coordinator = makeCoordinator(terrain)
        let renderer = frames()

        let bush = try #require(forage(on: terrain).first { $0.kind == .berries })

        coordinator.player.place(x: bush.x, z: bush.z, on: terrain)
        coordinator.renderer(renderer, updateAtTime: 1)
        #expect(coordinator.driver.offer?.id == bush.id)

        let request = tap(bush)
        coordinator.write { $0.take = request }
        coordinator.renderer(renderer, updateAtTime: 2)

        #expect(coordinator.driver.pickedAt[bush.id] != nil)
    }

    /// **"You woke at the fire, at dawn" is a promise the copy makes, so
    /// it is pinned exactly rather than approximately.**
    ///
    /// `wake` takes the moment rather than reading a clock, which is what
    /// lets this assert `startedAt == woke` instead of "some time near
    /// now". That matters: a coordinator's clock starts at construction, so
    /// a test that only checked "the clock reads dawn" milliseconds later
    /// would pass just as happily against a `wake` that never touched the
    /// clock at all — the exact shape of the three tests slice 1 shipped
    /// that could not fail.
    @Test func wakingPutsYouAtTheFireAtDawn() throws {
        let terrain = try island()
        let coordinator = makeCoordinator(terrain)

        let bush = try #require(forage(on: terrain).first { $0.kind == .berries })
        let startedWith = coordinator.clock.startedAt

        // Walk off, strip a bush, and die of it.
        coordinator.player.place(x: bush.x, z: bush.z, on: terrain)
        coordinator.driver.step(playerX: bush.x, playerZ: bush.z, playerHeight: 100,
                                dt: 1, isNight: false, now: Date())
        #expect(coordinator.driver.take(bush, now: Date()))
        coordinator.driver.step(playerX: bush.x, playerZ: bush.z, playerHeight: -100,
                                dt: 1_000_000, isNight: true, now: Date())
        #expect(coordinator.driver.state.isDead)

        let woke = Date()
        coordinator.wake(now: woke)

        // Dawn, to the instant.
        #expect(coordinator.clock.startedAt == woke)
        #expect(coordinator.clock.timeOfDay(at: woke) == 0)
        #expect(coordinator.clock.isNight(at: woke) == false)
        #expect(coordinator.clock.startedAt > startedWith)

        // At the fire, rested.
        #expect(coordinator.player.worldX == coordinator.campfire.worldX)
        #expect(coordinator.player.worldZ == coordinator.campfire.worldZ)
        #expect(coordinator.driver.state == .rested)
        #expect(coordinator.driver.state.isDead == false)

        // **And the island is untouched.** The bush stays picked: dying is
        // not a way to farm a stripped patch back to full, and nothing the
        // player built or spent is refunded by it. Death costs the session
        // — the clock above — and nothing else (F3).
        #expect(coordinator.driver.pickedAt[bush.id] != nil)
    }

    /// The tap has to reach the coordinator, not just the method. A wake
    /// wired to nothing would leave every assertion above passing.
    @Test func tappingThroughTheBlackoutWakesYou() throws {
        let terrain = try island()
        let coordinator = makeCoordinator(terrain)
        let renderer = frames()

        let startedWith = coordinator.clock.startedAt
        coordinator.driver.step(playerX: 0, playerZ: 0, playerHeight: -100,
                                dt: 1_000_000, isNight: true, now: Date())
        #expect(coordinator.driver.state.isDead)

        coordinator.renderer(renderer, updateAtTime: 1)
        #expect(coordinator.driver.state.isDead)
        #expect(coordinator.clock.startedAt == startedWith)

        coordinator.write { $0.wake = 1 }
        coordinator.renderer(renderer, updateAtTime: 2)

        #expect(coordinator.driver.state.isDead == false)
        #expect(coordinator.clock.startedAt > startedWith)
        #expect(coordinator.player.worldX == coordinator.campfire.worldX)
    }

    /// One tap is one take, however many frames pass afterwards. The
    /// counter is compared rather than watched for a rising edge, and a
    /// request left sitting in the inbox must not be re-handled every
    /// frame for the rest of the session — which, on a spring that is
    /// never exhausted, would be an endless free drink.
    @Test func aTapIsHandledOnceAndNotOnEveryFrameAfterIt() throws {
        let terrain = try island()
        let coordinator = makeCoordinator(terrain)
        let renderer = frames()

        let spring = try #require(forage(on: terrain).first { $0.kind == .spring })

        coordinator.player.place(x: spring.x, z: spring.z, on: terrain)
        coordinator.renderer(renderer, updateAtTime: 1)

        // Drain first, so a wrongly repeated drink has somewhere to show
        // up — at full water the clamp at 1 would absorb it completely and
        // the test would prove nothing. Done through the driver's own
        // public `step` rather than a test-only hook, and in one call
        // because the render loop caps dt at 0.1 s: draining this far
        // through frames would take twelve thousand of them.
        coordinator.driver.step(playerX: spring.x, playerZ: spring.z, playerHeight: 100,
                                dt: 1_800, isNight: false, now: Date())
        let thirsty = coordinator.driver.state.water
        #expect(thirsty < 0.5)

        let request = tap(spring)
        coordinator.write { $0.take = request }

        coordinator.renderer(renderer, updateAtTime: 2)
        let afterTheTake = coordinator.driver.state.water
        #expect(afterTheTake > thirsty)

        // Many more frames, no new tap. Water may only fall from here.
        for frame in 3...20 {
            coordinator.renderer(renderer, updateAtTime: TimeInterval(frame))
        }
        #expect(coordinator.driver.state.water < afterTheTake)
    }
}
