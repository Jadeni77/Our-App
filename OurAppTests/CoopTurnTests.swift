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

    @Test func aFinishedMatchCanBeUnfinishedByAnOlderTruth() throws {
        let store = try context()
        let match = CoopMatch(levelID: UUID(), participants: ["a", "b"], turnHolder: "a")
        match.finishedAt = .now
        store.insert(match)
        try store.save()

        // `finishedAt` is assigned unconditionally on apply: a match that could
        // never be un-finished would strand a level forever if one phone set it
        // by mistake.
        var envelope = match.envelope()
        envelope.fields.removeValue(forKey: "finishedAt")
        envelope.updatedAt = Date().addingTimeInterval(60)
        SyncApply.apply(envelope, in: store, localAuthorID: "b")
        try store.save()

        #expect(try store.fetch(FetchDescriptor<CoopMatch>()).first?.finishedAt == nil)
    }
}
