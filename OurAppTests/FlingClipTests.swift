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
