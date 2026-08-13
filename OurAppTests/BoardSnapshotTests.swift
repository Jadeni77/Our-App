import Foundation
import Testing
@testable import OurApp

struct BoardSnapshotTests {
    private func snapshot(_ ids: [String], alive: [Bool]? = nil) -> BoardSnapshot {
        BoardSnapshot(levelID: UUID(), bodies: ids.enumerated().map { index, id in
            BoardSnapshot.Body(id: id, kind: "piece",
                               x: Double(index), y: Double(index) * 2, angle: 0.5,
                               alive: alive?[index] ?? true)
        })
    }

    private func clip(_ ids: [String], finalPoses: [BodyPose], present: [Bool]) -> FlingClip {
        FlingClip(frameRate: 30, bodyIDs: ids,
                  frames: [.init(poses: finalPoses.map { _ in BodyPose(x: 0, y: 0, angle: 0) },
                                 present: present),
                           .init(poses: finalPoses, present: present)])
    }

    @Test func aSnapshotRoundTrips() throws {
        let original = snapshot(["a", "b", "c"], alive: [true, false, true])
        let decoded = try #require(BoardSnapshotCodec.decode(BoardSnapshotCodec.encode(original)))
        #expect(decoded == original)
    }

    @Test func rubbishDecodesToNilRatherThanCrashing() {
        #expect(BoardSnapshotCodec.decode(Data()) == nil)
        #expect(BoardSnapshotCodec.decode(Data("not a snapshot".utf8)) == nil)
    }

    @Test func aClipMatchingTheSnapshotIsAccepted() {
        let board = snapshot(["a", "b"])
        let recording = clip(["a", "b"],
                             finalPoses: [BodyPose(x: 1, y: 1, angle: 0), BodyPose(x: 2, y: 2, angle: 0)],
                             present: [true, true])
        #expect(CoopBoardRules.clip(recording, matches: board))
    }

    @Test func aClipInADifferentOrderIsRefused() {
        // Frames are positional, so ["b","a"] against ["a","b"] would animate
        // each body along the other's path: every piece moving smoothly, every
        // piece wrong. Membership isn't enough — order is the identity.
        let board = snapshot(["a", "b"])
        let swapped = clip(["b", "a"],
                           finalPoses: [BodyPose(x: 1, y: 1, angle: 0), BodyPose(x: 2, y: 2, angle: 0)],
                           present: [true, true])
        #expect(CoopBoardRules.clip(swapped, matches: board) == false)
        #expect(CoopBoardRules.settledState(from: swapped, startingAt: board) == nil)
    }

    @Test func aClipWithAMissingBodyIsRefused() {
        let board = snapshot(["a", "b", "c"])
        let short = clip(["a", "b"],
                         finalPoses: [BodyPose(x: 0, y: 0, angle: 0), BodyPose(x: 0, y: 0, angle: 0)],
                         present: [true, true])
        #expect(CoopBoardRules.clip(short, matches: board) == false)
    }

    @Test func theSettledStateComesFromTheClipsLastFrame() throws {
        let board = snapshot(["a", "b"])
        let recording = clip(["a", "b"],
                             finalPoses: [BodyPose(x: 7, y: 8, angle: 1.5),
                                          BodyPose(x: -3, y: 4, angle: 0.25)],
                             present: [true, false])

        // Derived, not sent separately: a snapshot and a clip that disagreed
        // about where a piece finished would leave the two phones playing
        // different games.
        let settled = try #require(CoopBoardRules.settledState(from: recording, startingAt: board))
        #expect(settled.bodies[0].x == 7)
        #expect(settled.bodies[0].angle == 1.5)
        #expect(settled.bodies[1].alive == false)
        #expect(settled.aliveBodies.map(\.id) == ["a"])
    }

    @Test func aDeadBodyNeverComesBack() throws {
        let board = snapshot(["a", "b"], alive: [true, false])
        // The clip says b is present — it shouldn't matter. A body destroyed on
        // an earlier turn must not resurrect because a later recording happened
        // to include a stale entry for it.
        let recording = clip(["a", "b"],
                             finalPoses: [BodyPose(x: 1, y: 1, angle: 0), BodyPose(x: 2, y: 2, angle: 0)],
                             present: [true, true])

        let settled = try #require(CoopBoardRules.settledState(from: recording, startingAt: board))
        #expect(settled.bodies[1].alive == false)
    }

    @Test func aSnapshotStaysSmallEnoughToTravelEveryTurn() {
        let big = snapshot((0..<60).map { "body-\($0)" })
        // Written once per turn alongside a ~15KB clip, so a couple of KB is
        // the budget. JSON is the right tool here precisely because it's cheap.
        #expect(BoardSnapshotCodec.encode(big).count < 12_000)
    }
}
