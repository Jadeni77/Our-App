import Foundation
import Testing
@testable import OurApp

@MainActor
struct JiggleControllerTests {
    // A 2×2 synthetic grid of 100pt tiles with 20pt gutters:
    //   a(0,0)   b(120,0)
    //   c(0,120) d(120,120)
    private let frames: [GamesLayout.ItemID: CGRect] = [
        .app("a"): CGRect(x: 0, y: 0, width: 100, height: 100),
        .app("b"): CGRect(x: 120, y: 0, width: 100, height: 100),
        .app("c"): CGRect(x: 0, y: 120, width: 100, height: 100),
        .app("d"): CGRect(x: 120, y: 120, width: 100, height: 100),
    ]
    private let order: [GamesLayout.ItemID] = [.app("a"), .app("b"), .app("c"), .app("d")]
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    @Test func hoveringAnotherTileCenterIsATargetThatArmsAfterTheDelay() {
        let jiggle = JiggleController()
        jiggle.beginDrag(.app("a"))
        let centerOfB = CGPoint(x: 170, y: 50)
        jiggle.updateDrag(location: centerOfB, frames: frames, order: order, now: t0)
        #expect(jiggle.intent == .target(.app("b")))
        jiggle.updateDrag(location: centerOfB, frames: frames, order: order,
                          now: t0.addingTimeInterval(0.5))
        #expect(jiggle.intent == .armedTarget(.app("b")))
    }

    @Test func movingOffATargetResetsTheArmTimer() {
        let jiggle = JiggleController()
        jiggle.beginDrag(.app("a"))
        jiggle.updateDrag(location: CGPoint(x: 170, y: 50), frames: frames,
                          order: order, now: t0)
        jiggle.updateDrag(location: CGPoint(x: 170, y: 170), frames: frames,
                          order: order, now: t0.addingTimeInterval(0.3))
        // New target (d) — old hover time must not carry over.
        jiggle.updateDrag(location: CGPoint(x: 170, y: 170), frames: frames,
                          order: order, now: t0.addingTimeInterval(0.5))
        #expect(jiggle.intent == .target(.app("d")))
    }

    @Test func tileEdgesAreReorderGapsNotTargets() {
        let jiggle = JiggleController()
        jiggle.beginDrag(.app("a"))
        // x=235 sits right of b's inset zone (b spans 120–220; inset keeps 140–200).
        jiggle.updateDrag(location: CGPoint(x: 235, y: 50), frames: frames,
                          order: order, now: t0)
        // Nearest center is b (index 0 with "a" removed), location follows it → 1.
        #expect(jiggle.intent == .reorder(insertAt: 1))
    }

    @Test func positionsBeforeATileInsertAtItsSlot() {
        let jiggle = JiggleController()
        jiggle.beginDrag(.app("d"))
        // Just left of b's center, same row → insert at b's slot (index 1: a,b,c order).
        jiggle.updateDrag(location: CGPoint(x: 130, y: 40), frames: frames,
                          order: order, now: t0)
        #expect(jiggle.intent == .reorder(insertAt: 1))
    }

    @Test func draggedCollectionsOnlyReorder() {
        let collectionID = UUID()
        var withCollection = frames
        withCollection[.collection(collectionID)] = CGRect(x: 240, y: 0, width: 100, height: 100)
        let jiggle = JiggleController()
        jiggle.beginDrag(.collection(collectionID))
        jiggle.updateDrag(location: CGPoint(x: 170, y: 50), frames: withCollection,
                          order: order + [.collection(collectionID)], now: t0)
        // Dead-center over b, but a collection can't be dropped onto anything.
        #expect(jiggle.intent == .reorder(insertAt: 1))
    }

    @Test func endDragReturnsTheFinalIntentAndResets() {
        let jiggle = JiggleController()
        jiggle.beginDrag(.app("a"))
        jiggle.updateDrag(location: CGPoint(x: 170, y: 50), frames: frames,
                          order: order, now: t0)
        let final = jiggle.endDrag()
        #expect(final == .target(.app("b")))
        #expect(jiggle.draggedItem == nil)
        #expect(jiggle.intent == .none)
    }
}
