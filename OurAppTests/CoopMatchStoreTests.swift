import Foundation
import SwiftData
import Testing
@testable import OurApp

/// The sequence, not the rules. Each rule is tested on its own elsewhere; this
/// is where a set of correct rules can still add up to a wrong game.
@MainActor
struct CoopMatchStoreTests {
    private let me = "author-a"
    private let her = "author-b"

    private func context() throws -> ModelContext {
        ModelContext(try Persistence.makeContainer(inMemory: true))
    }

    private func board(_ ids: [String]) -> BoardSnapshot {
        BoardSnapshot(levelID: UUID(), bodies: ids.map {
            BoardSnapshot.Body(id: $0, kind: "piece", x: 0, y: 0, angle: 0, alive: true)
        })
    }

    /// A fling that shifts everything a little and destroys nothing.
    private func clip(_ ids: [String], shift: Double) -> FlingClip {
        FlingClip(frameRate: 30, bodyIDs: ids, frames: [
            .init(poses: ids.map { _ in BodyPose(x: 0, y: 0, angle: 0) },
                  present: ids.map { _ in true }),
            .init(poses: ids.map { _ in BodyPose(x: shift, y: shift, angle: 0) },
                  present: ids.map { _ in true }),
        ])
    }

    @Test func aFullAlternationRunsTheTurnBackAndForth() throws {
        let store = try context()
        let ids = ["p0", "p1"]
        let match = CoopMatchStore.start(levelID: UUID(), participants: [me, her],
                                         firstTurn: me, board: board(ids), in: store)

        #expect(CoopMatchStore.takeTurn(clip: clip(ids, shift: 5), by: me,
                                        in: match, context: store) != nil)
        #expect(match.turnIndex == 1)
        #expect(match.turnHolder == her)

        // And now mine is refused, because it isn't mine to take.
        #expect(CoopMatchStore.takeTurn(clip: clip(ids, shift: 9), by: me,
                                        in: match, context: store) == nil)
        #expect(match.turnIndex == 1)

        #expect(CoopMatchStore.takeTurn(clip: clip(ids, shift: 9), by: her,
                                        in: match, context: store) != nil)
        #expect(match.turnIndex == 2)
        #expect(match.turnHolder == me)
    }

    @Test func theBoardCarriesForwardFromOneTurnToTheNext() throws {
        let store = try context()
        let ids = ["p0"]
        let match = CoopMatchStore.start(levelID: UUID(), participants: [me, her],
                                         firstTurn: me, board: board(ids), in: store)
        CoopMatchStore.takeTurn(clip: clip(ids, shift: 7), by: me, in: match, context: store)

        // The next turn must start from where the last one finished, or the two
        // phones are playing different games from turn two onwards.
        let carried = try #require(BoardSnapshotCodec.decode(match.boardState))
        #expect(carried.bodies[0].x == 7)
    }

    @Test func aTurnArrivingFromTheOtherPhoneAdvancesTheMatch() throws {
        let store = try context()
        let ids = ["p0"]
        let match = CoopMatchStore.start(levelID: UUID(), participants: [me, her],
                                         firstTurn: her, board: board(ids), in: store)

        // Hers, taken on her phone and delivered here.
        let hers = CoopTurn(matchID: match.id, index: 1, authorID: her,
                            clip: FlingClipCodec.encode(clip(ids, shift: 3)),
                            resultingState: BoardSnapshotCodec.encode(board(ids)))
        #expect(CoopMatchStore.apply(hers, to: match, context: store))
        #expect(match.turnHolder == me)
    }

    @Test func aRedeliveredTurnDoesNotAdvanceTheMatchTwice() throws {
        let store = try context()
        let ids = ["p0"]
        let match = CoopMatchStore.start(levelID: UUID(), participants: [me, her],
                                         firstTurn: her, board: board(ids), in: store)
        let hers = CoopTurn(matchID: match.id, index: 1, authorID: her,
                            resultingState: BoardSnapshotCodec.encode(board(ids)))

        #expect(CoopMatchStore.apply(hers, to: match, context: store))
        // Sync re-delivers routinely. Advancing twice would hand the turn back
        // to her and let her play two in a row.
        #expect(CoopMatchStore.apply(hers, to: match, context: store) == false)
        #expect(match.turnIndex == 1)
        #expect(match.turnHolder == me)
    }

    @Test func aClipThatDoesNotMatchTheBoardIsRefusedRatherThanPlayed() throws {
        let store = try context()
        let match = CoopMatchStore.start(levelID: UUID(), participants: [me, her],
                                         firstTurn: me, board: board(["p0", "p1"]), in: store)
        // A clip recorded against a different roster. Playing it would animate
        // the wrong bodies, silently.
        #expect(CoopMatchStore.takeTurn(clip: clip(["p9"], shift: 4), by: me,
                                        in: match, context: store) == nil)
        #expect(match.turnIndex == 0)
    }

    @Test func theTurnToWatchIsHersAndOnlyOnce() throws {
        let store = try context()
        let ids = ["p0"]
        let match = CoopMatchStore.start(levelID: UUID(), participants: [me, her],
                                         firstTurn: her, board: board(ids), in: store)
        let hers = CoopTurn(matchID: match.id, index: 1, authorID: her,
                            resultingState: BoardSnapshotCodec.encode(board(ids)))
        store.insert(hers)
        CoopMatchStore.apply(hers, to: match, context: store)

        #expect(CoopMatchStore.turnToWatch(in: match, viewer: me, context: store)?.id == hers.id)
        // She doesn't get shown her own fling back.
        #expect(CoopMatchStore.turnToWatch(in: match, viewer: her, context: store) == nil)
    }

    @Test func aLiveMatchIsFoundForItsLevelAndAFinishedOneIsNot() throws {
        let store = try context()
        let level = UUID()
        let match = CoopMatchStore.start(levelID: level, participants: [me, her],
                                         firstTurn: me, board: board(["p0"]), in: store)
        #expect(CoopMatchStore.liveMatch(forLevel: level, in: store)?.id == match.id)

        match.finishedAt = .now
        try store.save()
        #expect(CoopMatchStore.liveMatch(forLevel: level, in: store) == nil)
    }
}
