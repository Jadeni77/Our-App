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

@MainActor
struct CoopWatchedTurnsTests {
    private func defaults() -> UserDefaults {
        let suite = "coop.watched.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        store.removePersistentDomain(forName: suite)
        return store
    }

    private func match(turnIndex: Int, holder: String) -> CoopMatch {
        let match = CoopMatch(levelID: UUID(), participants: ["me", "her"], turnHolder: holder)
        match.turnIndex = turnIndex
        return match
    }

    @Test func aTurnThatArrivedForYouIsUnwatchedUntilYouWatchIt() {
        let store = defaults()
        let live = match(turnIndex: 3, holder: "me")
        #expect(CoopWatchedTurns.hasUnwatchedTurn(in: live, viewer: "me", defaults: store))

        CoopWatchedTurns.markWatched(3, of: live.id, defaults: store)
        #expect(CoopWatchedTurns.hasUnwatchedTurn(in: live, viewer: "me", defaults: store) == false)
    }

    @Test func youAreNotOfferedYourOwnFlingBack() {
        let store = defaults()
        // The turn is hers to take, so the last fling was yours.
        let live = match(turnIndex: 3, holder: "her")
        #expect(CoopWatchedTurns.hasUnwatchedTurn(in: live, viewer: "me", defaults: store) == false)
    }

    @Test func aFreshMatchHasNothingToWatch() {
        let store = defaults()
        #expect(CoopWatchedTurns.hasUnwatchedTurn(in: match(turnIndex: 0, holder: "me"),
                                                  viewer: "me", defaults: store) == false)
    }

    @Test func watchedNeverGoesBackwards() {
        let store = defaults()
        let id = UUID()
        CoopWatchedTurns.markWatched(5, of: id, defaults: store)
        // Sync delivers out of order routinely; an older turn arriving must not
        // make you re-watch flings you have already seen.
        CoopWatchedTurns.markWatched(2, of: id, defaults: store)
        #expect(CoopWatchedTurns.lastWatchedIndex(id, defaults: store) == 5)
    }
}

@MainActor
struct PairedPartnerTests {
    @Test func pairingRecordsWhoYouPairedWith() {
        SyncSecretStore.clear()
        defer { SyncSecretStore.clear() }

        // Without this, both phones hold a shared secret and still cannot name
        // the person on the other end — which makes a two-participant match
        // impossible to create. Co-op was unbuildable until pairing carried an
        // identity as well as a secret.
        #expect(SyncSecretStore.partnerAuthorID() == nil)
        SyncSecretStore.savePartner("her-install-id")
        #expect(SyncSecretStore.partnerAuthorID() == "her-install-id")
    }

    @Test func forgettingThePhoneForgetsThePartnerToo() {
        SyncSecretStore.save(Data([1, 2, 3]))
        SyncSecretStore.savePartner("her-install-id")
        SyncSecretStore.clear()

        // A phone that kept the secret but forgot who it belonged to would be
        // paired with nobody, and every match it created would name a stranger.
        #expect(SyncSecretStore.partnerAuthorID() == nil)
        #expect(SyncSecretStore.isPaired == false)
    }

    @Test func bothPairMessageKindsSurviveTheWire() throws {
        for request in [SyncWire.Request.pair(code: "123456", authorID: "me"),
                        SyncWire.Request.records(cursor: ["a": 1])] {
            let data = try JSONEncoder().encode(request)
            #expect(try JSONDecoder().decode(SyncWire.Request.self, from: data) == request)
        }
        let response = SyncWire.Response.paired(secret: Data([9]), authorID: "her")
        let data = try JSONEncoder().encode(response)
        #expect(try JSONDecoder().decode(SyncWire.Response.self, from: data) == response)
    }
}
