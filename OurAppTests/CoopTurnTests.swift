import Foundation
import SwiftData
import Testing
@testable import OurApp

@MainActor
struct CoopTurnRulesTests {
    private let me = "author-a"
    private let her = "author-b"

    private func match(holder: String? = nil, index: Int = 0) -> CoopMatch {
        let match = CoopMatch(levelID: UUID(), participants: ["author-a", "author-b"],
                              turnHolder: holder ?? "author-a")
        match.turnIndex = index
        return match
    }

    @Test func onlyTheTurnHolderMayFling() {
        let live = match(holder: me)
        // The owner's rule, and the whole permission model: you can only fling
        // when you hold the turn. It is also what makes an offline player
        // harmless — they were never entitled to a turn against a board that
        // had moved on.
        #expect(CoopTurnRules.mayFling(me, in: live))
        #expect(CoopTurnRules.mayFling(her, in: live) == false)
    }

    @Test func nobodyMayFlingOnAFinishedMatch() {
        let done = match(holder: me)
        done.finishedAt = .now
        #expect(CoopTurnRules.mayFling(me, in: done) == false)
    }

    @Test func aStrangerMayNotFling() {
        #expect(CoopTurnRules.mayFling("somebody-else", in: match()) == false)
    }

    @Test func theNextTurnIsAccepted() {
        let live = match(holder: me, index: 3)
        let turn = CoopTurn(matchID: live.id, index: 4, authorID: me)
        #expect(CoopTurnRules.verdict(for: turn, in: live) == .accept)
    }

    @Test func aRedeliveredTurnIsRecognisedRatherThanReapplied() {
        let live = match(holder: her, index: 4)
        // Sync re-delivers; the same turn must not advance the match twice.
        let turn = CoopTurn(matchID: live.id, index: 4, authorID: me)
        #expect(CoopTurnRules.verdict(for: turn, in: live) == .alreadyApplied)
    }

    @Test func aTurnFromTheFutureIsRefusedAndSaysWhatItExpected() {
        let live = match(holder: me, index: 2)
        let turn = CoopTurn(matchID: live.id, index: 7, authorID: me)
        // Naming the expected index is what lets the caller resync rather than
        // guess. A silent drop here is a match that quietly stops advancing.
        #expect(CoopTurnRules.verdict(for: turn, in: live) == .outOfOrder(expected: 3))
    }

    @Test func aTurnFromTheWrongPlayerIsRefused() {
        let live = match(holder: me, index: 0)
        let turn = CoopTurn(matchID: live.id, index: 1, authorID: her)
        #expect(CoopTurnRules.verdict(for: turn, in: live) == .notYourTurn)
    }

    @Test func theTurnPassesToTheOtherPlayer() {
        let live = match(holder: me)
        #expect(CoopTurnRules.nextHolder(after: me, in: live) == her)
        #expect(CoopTurnRules.nextHolder(after: her, in: live) == me)
    }
}

@MainActor
struct CoopSyncTests {
    private func context() throws -> ModelContext {
        ModelContext(try Persistence.makeContainer(inMemory: true))
    }

    @Test func aMatchRoundTripsThroughAnEnvelopeWithItsBoardIntact() throws {
        let store = try context()
        let board = Data((0..<64).map { UInt8($0) })
        let match = CoopMatch(levelID: UUID(), participants: ["a", "b"],
                              turnHolder: "a", boardState: board)
        match.turnIndex = 5
        store.insert(match)
        try store.save()

        let receiving = try context()
        SyncApply.apply(match.envelope(), in: receiving, localAuthorID: "b")
        try receiving.save()

        let arrived = try receiving.fetch(FetchDescriptor<CoopMatch>()).first
        #expect(arrived?.turnIndex == 5)
        #expect(arrived?.participants == ["a", "b"])
        // The board is authoritative — the clip is only what you watch.
        #expect(arrived?.boardState == board)
    }

    /// **The stall, exactly as it happened on the simulators.**
    ///
    /// Both phones create a match the moment the level is opened, and a match's
    /// id is its level's id — so the two creations are two writes to one
    /// record. She opened level 2 a few seconds after your shot, so her turn-0
    /// match was the *newer* write. Under LWW it won, and your turn was undone
    /// on both phones: turn 1 at ...549.673 lost to turn 0 at ...553.426.
    @Test func aFreshlyCreatedMatchCannotUndoATurnAlreadyTaken() throws {
        let levelID = UUID()
        let played = CoopMatch(levelID: levelID, participants: ["a", "b"],
                               turnHolder: "b", boardState: Data([9, 9, 9]))
        played.turnIndex = 1
        played.updatedAt = Date(timeIntervalSinceReferenceDate: 549.673)

        // Hers: same record, no turn taken, and four seconds later.
        let store = try context()
        let fresh = CoopMatch(levelID: levelID, participants: ["a", "b"],
                              turnHolder: "a", boardState: Data([1, 1, 1]))
        fresh.updatedAt = Date(timeIntervalSinceReferenceDate: 553.426)
        store.insert(fresh)
        try store.save()

        SyncApply.apply(played.envelope(), in: store, localAuthorID: "b")
        try store.save()

        let arrived = try #require(try store.fetch(FetchDescriptor<CoopMatch>()).first)
        #expect(arrived.turnIndex == 1)
        #expect(arrived.turnHolder == "b")
        #expect(arrived.boardState == Data([9, 9, 9]))
    }

    /// And the same in the other direction: her stale turn-0 record arriving on
    /// the phone that is already at turn 1 must change nothing.
    @Test func aStaleMatchArrivingLaterDoesNotRewindTheGame() throws {
        let levelID = UUID()
        let store = try context()
        let played = CoopMatch(levelID: levelID, participants: ["a", "b"],
                               turnHolder: "b", boardState: Data([9, 9, 9]))
        played.turnIndex = 1
        played.updatedAt = Date(timeIntervalSinceReferenceDate: 549.673)
        store.insert(played)
        try store.save()

        let stale = CoopMatch(levelID: levelID, participants: ["a", "b"],
                              turnHolder: "a", boardState: Data([1, 1, 1]))
        stale.updatedAt = Date(timeIntervalSinceReferenceDate: 553.426)
        SyncApply.apply(stale.envelope(), in: store, localAuthorID: "b")
        try store.save()

        let arrived = try #require(try store.fetch(FetchDescriptor<CoopMatch>()).first)
        #expect(arrived.turnIndex == 1)
        #expect(arrived.turnHolder == "b")
    }

    /// A level you cleared together stays cleared. `finishedAt` is derived from
    /// a board whose bodies only ever die, so a record without it is stale news
    /// rather than a retraction.
    @Test func aMatchAlreadyWonIsNotUnwonByAnEarlierRecord() throws {
        let levelID = UUID()
        let store = try context()
        let won = CoopMatch(levelID: levelID, participants: ["a", "b"],
                            turnHolder: "b", boardState: Data([9]))
        won.turnIndex = 2
        won.finishedAt = Date(timeIntervalSinceReferenceDate: 600)
        store.insert(won)
        try store.save()

        let unfinished = CoopMatch(levelID: levelID, participants: ["a", "b"],
                                   turnHolder: "b", boardState: Data([9]))
        unfinished.turnIndex = 2
        unfinished.updatedAt = Date(timeIntervalSinceReferenceDate: 900)
        SyncApply.apply(unfinished.envelope(), in: store, localAuthorID: "b")
        try store.save()

        let arrived = try #require(try store.fetch(FetchDescriptor<CoopMatch>()).first)
        #expect(arrived.finishedAt != nil)
    }

    @Test func aTurnArrivingTwiceIsNotStoredTwice() throws {
        let store = try context()
        let turn = CoopTurn(matchID: UUID(), index: 1, authorID: "a",
                            clip: Data([1, 2, 3]), resultingState: Data([4]))
        let envelope = turn.envelope()

        SyncApply.apply(envelope, in: store, localAuthorID: "b")
        let second = SyncApply.apply(envelope, in: store, localAuthorID: "b")
        try store.save()

        // Append-only: turns are never rewritten, so redelivery is a no-op
        // rather than a merge that could disturb history.
        #expect(second == false)
        #expect(try store.fetchCount(FetchDescriptor<CoopTurn>()) == 1)
    }

    @Test func aTurnWithNoClipStillCarriesItsResultingState() throws {
        let store = try context()
        let turn = CoopTurn(matchID: UUID(), index: 1, authorID: "a",
                            clip: Data(), resultingState: Data([9, 9]))
        SyncApply.apply(turn.envelope(), in: store, localAuthorID: "b")
        try store.save()

        // Losing the show must never mean losing the game.
        let arrived = try store.fetch(FetchDescriptor<CoopTurn>()).first
        #expect(arrived?.clip.isEmpty == true)
        #expect(arrived?.resultingState == Data([9, 9]))
    }

    /// **This test used to assert the opposite**, on the reasoning that a match
    /// which could never be un-finished would strand a level forever if a phone
    /// set `finishedAt` by mistake.
    ///
    /// A phone can no longer set it by mistake. Finishing is derived from the
    /// board — no gloom left alive — and bodies only ever die, so the condition
    /// is monotonic and cannot be reached in error. What the old rule bought
    /// was protection against a hazard that no longer exists; what it cost is
    /// real, because both phones write this record and a turn-0 write arriving
    /// late would have un-won a level the two of you had cleared.
    @Test func aFinishedMatchStaysFinishedWhenAnOlderRecordArrives() throws {
        let store = try context()
        let match = CoopMatch(levelID: UUID(), participants: ["a", "b"], turnHolder: "a")
        match.finishedAt = .now
        store.insert(match)
        try store.save()

        var envelope = match.envelope()
        envelope.fields.removeValue(forKey: "finishedAt")
        envelope.updatedAt = Date().addingTimeInterval(60)
        SyncApply.apply(envelope, in: store, localAuthorID: "b")
        try store.save()

        #expect(try store.fetch(FetchDescriptor<CoopMatch>()).first?.finishedAt != nil)
    }
}

@MainActor
struct CoopFirstTurnTests {
    @Test func bothPhonesAgreeWhoGoesFirstWithoutTalking() {
        // The bug this replaces: "whoever tapped Start first" is a race. With
        // no sync in between, both phones believed they had won it, both took
        // "the first turn", and both then sat waiting for a turn the other had
        // never sent.
        #expect(CoopTurnRules.firstTurn(among: ["b", "a"])
                == CoopTurnRules.firstTurn(among: ["a", "b"]))
        #expect(CoopTurnRules.firstTurn(among: ["b", "a"]) == "a")
    }

    @Test func firstTurnIsAlwaysAParticipant() {
        let ids = ["zebra-install", "aardvark-install"]
        #expect(ids.contains(CoopTurnRules.firstTurn(among: ids)))
    }
}
