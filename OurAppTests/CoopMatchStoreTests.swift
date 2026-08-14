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

    /// **Every board here carries a gloom**, added automatically, because a
    /// board with nothing gloomy left standing is a *cleared* board — so a test
    /// that forgot one would quietly be playing a level that was already won.
    private func board(_ ids: [String]) -> BoardSnapshot {
        BoardSnapshot(levelID: UUID(), bodies: (ids + [gloom]).map {
            BoardSnapshot.Body(id: $0, kind: $0 == gloom ? "gloom" : "piece",
                               x: 0, y: 0, angle: 0, alive: true)
        })
    }

    private let gloom = "g0"

    /// A fling that shifts everything a little. `clearing` is the shot that
    /// wins it: the gloom stops being present, which is how a clip says a body
    /// is gone.
    private func clip(_ ids: [String], shift: Double, clearing: Bool = false) -> FlingClip {
        let all = ids + [gloom]
        return FlingClip(frameRate: 30, bodyIDs: all, frames: [
            .init(poses: all.map { _ in BodyPose(x: 0, y: 0, angle: 0) },
                  present: all.map { _ in true }),
            .init(poses: all.map { _ in BodyPose(x: shift, y: shift, angle: 0) },
                  present: all.map { !clearing || $0 != gloom }),
        ])
    }

    /// Winning has to *end* the match. It didn't: nothing in the app wrote
    /// `finishedAt`, so clearing a level just passed the cleared board to the
    /// other player and both phones sat on "waiting" over a finished game.
    @Test func clearingTheBoardFinishesTheMatch() throws {
        let store = try context()
        let ids = ["p0", "p1"]
        let match = CoopMatchStore.start(levelID: UUID(), participants: [me, her],
                                         firstTurn: me, board: board(ids), in: store)

        #expect(CoopMatchStore.takeTurn(clip: clip(ids, shift: 4, clearing: true),
                                        by: me, in: match, context: store) != nil)
        #expect(match.finishedAt != nil)
    }

    /// And it has to end on *her* phone too, which never took the winning shot
    /// — she only watched it. Both derive the ending from the same board, so
    /// neither has to be told.
    @Test func theWatchingPhoneAlsoSeesTheMatchFinish() throws {
        let mine = try context()
        let hers = try context()
        let ids = ["p0", "p1"]
        let levelID = UUID()
        let startingBoard = board(ids)

        let myMatch = CoopMatchStore.start(levelID: levelID, participants: [me, her],
                                           firstTurn: me, board: startingBoard, in: mine)
        let herMatch = CoopMatchStore.start(levelID: levelID, participants: [me, her],
                                            firstTurn: me, board: startingBoard, in: hers)

        let winning = try #require(CoopMatchStore.takeTurn(
            clip: clip(ids, shift: 4, clearing: true), by: me, in: myMatch, context: mine))

        // The turn as it arrives on her phone.
        let arrived = CoopTurn(matchID: herMatch.id, index: winning.index, authorID: me,
                               clip: winning.clip, resultingState: winning.resultingState)
        hers.insert(arrived)
        #expect(CoopMatchStore.apply(arrived, to: herMatch, context: hers))
        #expect(herMatch.finishedAt != nil)
    }

    /// A match already sitting on a cleared board — which is what the build
    /// that couldn't finish a match left behind on both simulators — heals on
    /// load rather than waiting forever for a turn that will never come.
    @Test func aMatchLeftOnAClearedBoardFinishesOnLoad() throws {
        let store = try context()
        var cleared = board(["p0"])
        for index in cleared.bodies.indices where cleared.bodies[index].kind == "gloom" {
            cleared.bodies[index].alive = false
        }
        let match = CoopMatchStore.start(levelID: UUID(), participants: [me, her],
                                         firstTurn: me, board: cleared, in: store)
        #expect(match.finishedAt == nil)

        #expect(CoopMatchStore.reconcile(match, context: store))
        #expect(match.finishedAt != nil)
        // Idempotent: a second load must not keep rewriting the timestamp, or
        // every open would look like a change worth syncing.
        #expect(CoopMatchStore.reconcile(match, context: store) == false)
    }

    /// Re-entering a level you cleared together must not insert a second match.
    /// A match's id *is* its level's id, so two rows would mean one identity
    /// with two records and a merge that picks between them arbitrarily.
    @Test func startingAClearedLevelReturnsTheMatchYouAlreadyPlayed() throws {
        let store = try context()
        let ids = ["p0", "p1"]
        let levelID = UUID()
        let match = CoopMatchStore.start(levelID: levelID, participants: [me, her],
                                         firstTurn: me, board: board(ids), in: store)
        CoopMatchStore.takeTurn(clip: clip(ids, shift: 4, clearing: true),
                                by: me, in: match, context: store)

        let again = CoopMatchStore.start(levelID: levelID, participants: [me, her],
                                         firstTurn: me, board: board(ids), in: store)
        #expect(again === match)
        let all = try store.fetch(FetchDescriptor<CoopMatch>())
        #expect(all.count == 1)
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

@MainActor
struct PairedStateTests {
    @Test func aSecretWithoutAPartnerIsNotPaired() {
        SyncSecretStore.clear()
        defer { SyncSecretStore.clear() }

        // The state an older build left behind: a secret, and no idea whose it
        // is. Reporting that as paired let the lobby offer a Start button that
        // silently did nothing — reported, reasonably, as the app freezing.
        SyncSecretStore.save(Data([1, 2, 3]))
        #expect(SyncSecretStore.isPaired == false)

        SyncSecretStore.savePartner("her-install-id")
        #expect(SyncSecretStore.isPaired)
    }
}

@MainActor
struct CoopMatchIdentityTests {
    private func context() throws -> ModelContext {
        ModelContext(try Persistence.makeContainer(inMemory: true))
    }

    private func board() -> BoardSnapshot {
        BoardSnapshot(levelID: UUID(), bodies: [])
    }

    @Test func bothPhonesStartingTheSameLevelProduceOneMatch() throws {
        let level = UUID()
        let mine = try context()

        // She tapped Start too, a second earlier, on her phone.
        let hers = CoopMatch(levelID: level, participants: ["her", "me"], turnHolder: "her")
        SyncApply.apply(hers.envelope(), in: mine, localAuthorID: "me")
        try mine.save()

        CoopMatchStore.start(levelID: level, participants: ["me", "her"],
                             firstTurn: "me", board: board(), in: mine)

        // Two matches for one level means each device picks a different one and
        // both sit on "Waiting for her" forever — which is exactly what shipped.
        #expect(try mine.fetchCount(FetchDescriptor<CoopMatch>()) == 1)
    }

    @Test func aMatchesIdentityIsItsLevel() {
        let level = UUID()
        let a = CoopMatch(levelID: level, participants: ["a", "b"], turnHolder: "a")
        let b = CoopMatch(levelID: level, participants: ["b", "a"], turnHolder: "b")
        // Independently created on two phones, they must be the same record.
        #expect(a.id == b.id)
    }
}

/// Continuing a board, rather than starting the level again.
@MainActor
struct CoopBoardContinuityTests {
    private func context() throws -> ModelContext {
        ModelContext(try Persistence.makeContainer(inMemory: true))
    }

    /// **The clip has to be replayed over the board it was recorded against.**
    ///
    /// The view handed it `match.boardState`, which is the board *after* the
    /// turn — so every piece the shot destroyed was already gone before the
    /// replay began, and all you saw was the survivors moving a little at the
    /// end. The board a turn started from is the previous turn's result.
    @Test func aTurnReplaysOverTheBoardItWasPlayedOn() throws {
        let store = try context()
        let level = CampaignCatalog.bundled.levels[0]
        let matchID = UUID()

        let first = CoopTurn(matchID: matchID, index: 1, authorID: "a", clip: Data(),
                             resultingState: BoardSnapshotCodec.encode(
                                BoardSnapshot(levelID: level.id, bodies: [
                                    .init(id: "p0", kind: "piece", x: 7, y: 7,
                                          angle: 0, alive: true)])))
        store.insert(first)
        let second = CoopTurn(matchID: matchID, index: 2, authorID: "b",
                              clip: Data(), resultingState: Data())
        store.insert(second)
        try store.save()

        let board = try #require(CoopMatchStore.startingBoard(for: second, level: level,
                                                              context: store))
        #expect(board.bodies.first?.x == 7)
    }

    /// The first turn of a match has no previous turn, and starts from the
    /// level as authored rather than from nothing.
    @Test func theFirstTurnStartsFromTheLevelItself() throws {
        let store = try context()
        let level = CampaignCatalog.bundled.levels[0]
        let turn = CoopTurn(matchID: UUID(), index: 1, authorID: "a",
                            clip: Data(), resultingState: Data())

        let board = try #require(CoopMatchStore.startingBoard(for: turn, level: level,
                                                              context: store))
        let opening = BoardSnapshot(startOf: level)
        let allAlive = board.bodies.allSatisfy(\.alive)
        #expect(board.bodies.count == opening.bodies.count)
        #expect(allAlive)
    }
}
