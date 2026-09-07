import CoreGraphics
import Foundation
import Testing
@testable import FarshoreKit

/// **The invariant here is the one the old code broke**, and it is worth
/// stating plainly: the same swipe must turn you the same amount however many
/// callbacks it arrives in.
///
/// `DragGesture.Value.translation` is the total offset since the drag began,
/// so subtracting it every `onChanged` integrated the drag — the turn scaled
/// with the drag's *duration* and with the display's refresh rate instead of
/// with distance. Nothing could catch that while the arithmetic lived inside a
/// gesture closure, which is why `TurnTracker` exists at all.
struct TurnTrackerTests {
    /// Feeds a stroke as cumulative translations, the way SwiftUI does.
    private func turn(strokeTo end: CGFloat, inSteps steps: Int) -> Double {
        var tracker = TurnTracker()
        var heading = 0.0
        for step in 1...steps {
            heading += tracker.headingChange(translation: end * CGFloat(step) / CGFloat(steps))
        }
        return heading
    }

    /// **The regression test.** 30 events is a 200 pt swipe over half a second
    /// at 60 Hz; 120 is the same swipe on a 120 Hz ProMotion display taking a
    /// full second. Under the old integrating code those four numbers were all
    /// different — and by large factors, not rounding — so a sensitivity
    /// tuned on the owner's phone was wrong on any other.
    @Test func theSameSwipeTurnsTheSameAmountHoweverManyEventsItArrivesIn() {
        let reference = turn(strokeTo: 200, inSteps: 1)
        for steps in [2, 5, 30, 60, 120, 400] {
            #expect(abs(turn(strokeTo: 200, inSteps: steps) - reference) < 0.000_000_1)
        }
    }

    /// Holding the finger still is the clearest statement of the same bug: the
    /// world used to keep spinning, one whole swipe's worth of turn per event,
    /// for as long as you did not move.
    @Test func holdingStillTurnsNothing() {
        var tracker = TurnTracker()
        _ = tracker.headingChange(translation: 200)
        for _ in 0..<60 {
            #expect(tracker.headingChange(translation: 200) == 0)
        }
    }

    /// The rate is per point of travel, and it is the named constant's job.
    @Test func theTurnIsProportionalToDistanceTravelled() {
        #expect(abs(turn(strokeTo: 100, inSteps: 10) - -100 * TurnTracker.radiansPerPoint) < 0.000_000_1)
        #expect(abs(turn(strokeTo: 400, inSteps: 10) - -400 * TurnTracker.radiansPerPoint) < 0.000_000_1)
        // Twice the distance, twice the turn — whatever the constant becomes.
        #expect(abs(turn(strokeTo: 400, inSteps: 10) - 2 * turn(strokeTo: 200, inSteps: 10)) < 0.000_000_1)
    }

    /// Dragging right swings the view right, which means rotating the world
    /// the other way. Sign errors in this family are the reason the previous
    /// commit on this branch existed (strafe was inverted at every heading).
    @Test func draggingRightTurnsTheOppositeWayFromDraggingLeft() {
        #expect(turn(strokeTo: 200, inSteps: 10) < 0)
        #expect(turn(strokeTo: -200, inSteps: 10) > 0)
        #expect(abs(turn(strokeTo: 200, inSteps: 10) + turn(strokeTo: -200, inSteps: 10)) < 0.000_000_1)
    }

    /// **Without `end()` the next drag starts with a stale baseline** and its
    /// first callback snaps the heading by the whole of the previous drag,
    /// backwards. A one-line omission with a very visible symptom, and nothing
    /// else in the package would notice it.
    @Test func endingADragResetsTheBaselineForTheNext() {
        var tracker = TurnTracker()
        _ = tracker.headingChange(translation: 300)
        tracker.end()
        // A fresh drag's first event reports a small translation, not one
        // continuing from 300.
        let firstOfNextDrag = tracker.headingChange(translation: 10)
        #expect(abs(firstOfNextDrag - -10 * TurnTracker.radiansPerPoint) < 0.000_000_1)
    }

    /// A back-and-forth stroke that returns to where it started leaves the
    /// heading where it started. True of a delta tracker, false of anything
    /// that accumulates magnitude.
    @Test func aStrokeThatReturnsToItsOriginLeavesTheHeadingUnchanged() {
        var tracker = TurnTracker()
        var heading = 0.0
        for translation: CGFloat in [40, 90, 160, 120, 60, 0] {
            heading += tracker.headingChange(translation: translation)
        }
        #expect(abs(heading) < 0.000_000_1)
    }
}
