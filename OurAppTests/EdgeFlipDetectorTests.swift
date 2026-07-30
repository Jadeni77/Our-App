import Foundation
import Testing
@testable import OurApp

struct EdgeFlipDetectorTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)
    private let width: CGFloat = 400

    @Test func enteringTheZoneArmsButNeverFiresImmediately() {
        var detector = EdgeFlipDetector()
        #expect(detector.update(x: 10, width: width, now: t0) == nil)
        #expect(detector.update(x: 10, width: width, now: t0 + 0.2) == nil)
    }

    @Test func firesAfterTheDwellAndKeepsFiringAtTheDwellCadence() {
        var detector = EdgeFlipDetector()
        _ = detector.update(x: 10, width: width, now: t0)
        #expect(detector.update(x: 10, width: width, now: t0 + 0.36) == .back)
        // Still holding: quiet until another dwell elapses, then fires again.
        #expect(detector.update(x: 10, width: width, now: t0 + 0.5) == nil)
        #expect(detector.update(x: 10, width: width, now: t0 + 0.72) == .back)
    }

    @Test func trailingEdgeFlipsForward() {
        var detector = EdgeFlipDetector()
        _ = detector.update(x: 390, width: width, now: t0)
        #expect(detector.update(x: 390, width: width, now: t0 + 0.36) == .forward)
    }

    @Test func leavingTheZoneDisarmsAndReturningRestartsTheClock() {
        var detector = EdgeFlipDetector()
        _ = detector.update(x: 10, width: width, now: t0)
        #expect(detector.update(x: 200, width: width, now: t0 + 0.2) == nil)
        // Back in the zone: the old dwell time must not count.
        #expect(detector.update(x: 10, width: width, now: t0 + 0.4) == nil)
        #expect(detector.update(x: 10, width: width, now: t0 + 0.76) == .back)
    }

    @Test func switchingEdgesRearmsInsteadOfFiring() {
        var detector = EdgeFlipDetector()
        _ = detector.update(x: 10, width: width, now: t0)
        #expect(detector.update(x: 390, width: width, now: t0 + 0.36) == nil)
        #expect(detector.update(x: 390, width: width, now: t0 + 0.72) == .forward)
    }

    @Test func theMiddleOfTheScreenNeverFires() {
        var detector = EdgeFlipDetector()
        #expect(detector.update(x: 200, width: width, now: t0) == nil)
        #expect(detector.update(x: 200, width: width, now: t0 + 1) == nil)
    }

    @Test func resetDropsTheArmedState() {
        var detector = EdgeFlipDetector()
        _ = detector.update(x: 10, width: width, now: t0)
        detector.reset()
        #expect(detector.update(x: 10, width: width, now: t0 + 0.36) == nil)
        #expect(detector.update(x: 10, width: width, now: t0 + 0.72) == .back)
    }
}
