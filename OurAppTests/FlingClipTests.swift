import Foundation
import Testing
@testable import OurApp

struct FlingClipCodecTests {
    private func clip(bodies: Int, frames: Int) -> FlingClip {
        let ids = (0..<bodies).map { "body-\($0)" }
        let sampled = (0..<frames).map { frame in
            FlingClip.Frame(
                poses: (0..<bodies).map { body in
                    BodyPose(x: Double(frame) * 1.25 + Double(body),
                             y: Double(body) * 3.5 - Double(frame),
                             angle: Double(frame) * 0.1 + Double(body))
                },
                present: (0..<bodies).map { _ in true })
        }
        return FlingClip(frameRate: 30, bodyIDs: ids, frames: sampled)
    }

    @Test func aClipSurvivesTheRoundTripWithinQuantisationError() throws {
        let original = clip(bodies: 6, frames: 12)
        let decoded = try #require(FlingClipCodec.decode(FlingClipCodec.encode(original)))

        #expect(decoded.frameRate == original.frameRate)
        #expect(decoded.bodyIDs == original.bodyIDs)
        #expect(decoded.frames.count == original.frames.count)

        // Positions are quantised to 1/scale of a point, so exact equality is
        // the wrong assertion — half a quantum is the honest bound.
        let tolerance = 1 / FlingClipCodec.scale / 2
        for (before, after) in zip(original.frames, decoded.frames) {
            for (a, b) in zip(before.poses, after.poses) {
                #expect(abs(a.x - b.x) <= tolerance)
                #expect(abs(a.y - b.y) <= tolerance)
                let turn = 2 * Double.pi
                let expected = a.angle.truncatingRemainder(dividingBy: turn)
                let normalised = expected < 0 ? expected + turn : expected
                #expect(abs(normalised - b.angle) <= turn / 65536)
            }
        }
    }

    @Test func aDestroyedBodyStopsBeingPresent() throws {
        var original = clip(bodies: 3, frames: 4)
        // A piece shattered halfway through. Without presence bits it would
        // freeze in place on the watching phone rather than vanishing.
        original.frames[2].present = [true, false, true]
        original.frames[3].present = [true, false, false]

        let decoded = try #require(FlingClipCodec.decode(FlingClipCodec.encode(original)))
        #expect(decoded.frames[1].present == [true, true, true])
        #expect(decoded.frames[2].present == [true, false, true])
        #expect(decoded.frames[3].present == [true, false, false])
    }

    /// The crash that took the app down mid-fling on level 2, on real hardware.
    ///
    /// Every angle these tests fed the encoder was a tidy positive — which is
    /// why a suite this size never saw it. A body at rest sits at a negative
    /// epsilon constantly, and that is the one input that overflows: adding a
    /// full turn to it rounds to *exactly* a full turn in binary floating
    /// point, so the tick lands on 65536, one past what a `UInt16` holds.
    @Test func anAngleJustBelowZeroDoesNotOverflow() throws {
        // -1e-16 is not a contrived value: it is a settled body, and a fling's
        // last frame is nothing but settled bodies. The rest bracket the same
        // boundary from the other side and from several turns out.
        let angles: [Double] = [-1e-16, -.ulpOfOne, -0.0,
                                2 * .pi - 1e-16, -2 * .pi, -19.9,
                                .nan, .infinity, -.infinity]

        for angle in angles {
            let clip = FlingClip(frameRate: 30, bodyIDs: ["settled"],
                                 frames: [.init(poses: [BodyPose(x: 0, y: 0, angle: angle)],
                                                present: [true])])
            // Encoding is the assertion — the failure mode was a trap, not a
            // wrong number.
            let decoded = try #require(FlingClipCodec.decode(FlingClipCodec.encode(clip)))
            let round = try #require(decoded.frames.first?.poses.first?.angle)
            #expect(round >= 0 && round < 2 * .pi)
        }
    }

    /// A full turn and no turn are the same angle, so the wrap has to land on
    /// zero rather than merely somewhere in range.
    @Test func aFullTurnReadsBackAsNoTurn() throws {
        let clip = FlingClip(frameRate: 30, bodyIDs: ["spun"],
                             frames: [.init(poses: [BodyPose(x: 0, y: 0, angle: -1e-16)],
                                            present: [true])])
        let decoded = try #require(FlingClipCodec.decode(FlingClipCodec.encode(clip)))
        #expect(decoded.frames[0].poses[0].angle == 0)
    }

    @Test func aBodyFlungWellOffScreenClampsRatherThanWrapping() throws {
        let far = FlingClip(frameRate: 30, bodyIDs: ["escapee"],
                            frames: [.init(poses: [BodyPose(x: 500_000, y: -500_000, angle: 0)],
                                           present: [true])])
        let decoded = try #require(FlingClipCodec.decode(FlingClipCodec.encode(far)))

        // Overflow would wrap a body that flew off the top of the world round
        // to the bottom of it — visibly wrong, and only on the watching phone.
        #expect(decoded.frames[0].poses[0].x > 8_000)
        #expect(decoded.frames[0].poses[0].y < -8_000)
    }

    @Test func anEmptyClipRoundTrips() throws {
        let empty = FlingClip(frameRate: 30, bodyIDs: [], frames: [])
        let decoded = try #require(FlingClipCodec.decode(FlingClipCodec.encode(empty)))
        #expect(decoded.frames.isEmpty)
        #expect(decoded.bodyIDs.isEmpty)
    }

    @Test func rubbishDecodesToNilRatherThanCrashing() {
        // A clip is the one field that arrives from another phone and is parsed
        // rather than read. Truncation must be a nil, never a trap.
        #expect(FlingClipCodec.decode(Data()) == nil)
        #expect(FlingClipCodec.decode(Data("not a clip at all".utf8)) == nil)

        let good = FlingClipCodec.encode(clip(bodies: 4, frames: 6))
        for cut in [4, 12, good.count - 1] {
            #expect(FlingClipCodec.decode(good.prefix(cut)) == nil)
        }
    }

    @Test func aRealisticFlingFitsComfortablyInsideARecord() {
        // 40 bodies, two seconds at 30Hz — the shape of an actual fling.
        let realistic = FlingClipCodec.encode(clip(bodies: 40, frames: 60))
        #expect(realistic.count < 20_000)
        // And the claim that it beats a photo: thumbnails alone are ~10KB.
        #expect(realistic.count < 1_000_000)
    }

    @Test func durationFollowsTheFrameRate() {
        #expect(abs(clip(bodies: 2, frames: 60).duration - 2.0) < 0.001)
        #expect(FlingClip(frameRate: 0, bodyIDs: [], frames: []).duration == 0)
    }
}

@MainActor
final class FakeBody: RecordableBody {
    let recordingID: String
    var recordedPose: BodyPose
    var isRecordingAlive: Bool

    init(_ id: String, x: Double = 0, y: Double = 0, angle: Double = 0) {
        recordingID = id
        recordedPose = BodyPose(x: x, y: y, angle: angle)
        isRecordingAlive = true
    }
}

@MainActor
struct FlingRecorderTests {
    @Test func samplingIsPacedByTimeNotByHowOftenItIsCalled() {
        let body = FakeBody("a")
        let recorder = FlingRecorder(bodies: [body], frameRate: 30)

        // update(_:) fires at the display's rate — 60Hz here, 120 on a ProMotion
        // phone. Recording every call would make a clip's length depend on
        // which handset took the turn.
        var captured = 0
        for step in 0..<60 {
            if recorder.sample(at: Double(step) / 60.0) { captured += 1 }
        }
        #expect(captured == 30)
        #expect(recorder.finish().frames.count == 30)
    }

    @Test func aDestroyedBodyIsRecordedAsGoneFromThatFrameOn() {
        let alive = FakeBody("a"), doomed = FakeBody("b")
        let recorder = FlingRecorder(bodies: [alive, doomed], frameRate: 30)

        recorder.sample(at: 0)
        doomed.isRecordingAlive = false
        recorder.sample(at: 1.0 / 30)

        let clip = recorder.finish()
        #expect(clip.frames[0].present == [true, true])
        #expect(clip.frames[1].present == [true, false])
        #expect(clip.bodyIDs == ["a", "b"])
    }

    @Test func aLongFrameCatchesUpRatherThanDrifting() {
        let recorder = FlingRecorder(bodies: [FakeBody("a")], frameRate: 30)
        recorder.sample(at: 0)
        // A hitch: the next call arrives half a second late. Without catch-up
        // the recorder would then fire on every call trying to make up 15
        // frames it can never recover.
        recorder.sample(at: 0.5)
        let immediatelyAfter = recorder.sample(at: 0.5)
        #expect(immediatelyAfter == false)
    }
}

struct FlingPlayerTests {
    private func clip() -> FlingClip {
        FlingClip(frameRate: 10, bodyIDs: ["a"], frames: [
            .init(poses: [BodyPose(x: 0, y: 0, angle: 0)], present: [true]),
            .init(poses: [BodyPose(x: 10, y: 20, angle: 1)], present: [true]),
        ])
    }

    @Test func positionsInterpolateBetweenFrames() throws {
        // A 30Hz clip drawn on a 60 or 120Hz screen would visibly step without
        // this.
        let midway = try #require(FlingPlayer.sample(clip(), at: 0.05))
        #expect(abs(midway.poses[0].x - 5) < 0.001)
        #expect(abs(midway.poses[0].y - 10) < 0.001)
    }

    @Test func timeBeforeAndAfterTheClipClamps() throws {
        let early = try #require(FlingPlayer.sample(clip(), at: -5))
        #expect(early.poses[0].x == 0)
        // A watcher joining late should see the final rubble, not nothing.
        let late = try #require(FlingPlayer.sample(clip(), at: 99))
        #expect(late.poses[0].x == 10)
    }

    @Test func rotationTakesTheShortWayRoundTheWrap() {
        let turn = 2 * Double.pi
        // A piece spinning past 2π wraps from ~6.28 to ~0. Interpolating that
        // linearly spins it almost a full turn *backwards* in one frame.
        let crossing = FlingPlayer.interpolate(angle: turn - 0.1, to: 0.1, t: 0.5)
        #expect(abs(crossing - 0) < 0.001 || abs(crossing - turn) < 0.001)

        let ordinary = FlingPlayer.interpolate(angle: 1.0, to: 2.0, t: 0.5)
        #expect(abs(ordinary - 1.5) < 0.001)
    }

    @Test func presenceDoesNotInterpolate() throws {
        var dying = clip()
        dying.frames[1].present = [false]
        // A body is alive or it isn't; the frame it dies in is the frame it
        // should disappear, not a fade.
        let midway = try #require(FlingPlayer.sample(dying, at: 0.05))
        #expect(midway.present == [true])
        let after = try #require(FlingPlayer.sample(dying, at: 0.15))
        #expect(after.present == [false])
    }

    @Test func anEmptyClipHasNothingToShow() {
        #expect(FlingPlayer.sample(FlingClip(frameRate: 30, bodyIDs: [], frames: []), at: 0) == nil)
    }
}
