import Foundation
import SwiftData

/// Starting a match, taking a turn, and folding in a turn that arrived.
///
/// Thin on purpose: every decision it makes is already a tested rule
/// (`CoopTurnRules`, `CoopBoardRules`). What lives here is the *sequence* —
/// which is where a rule can be right and the game still wrong.
@MainActor
enum CoopMatchStore {
    /// The match in progress for a level, if any.
    static func liveMatch(forLevel levelID: UUID, in context: ModelContext) -> CoopMatch? {
        let all = try? context.fetch(FetchDescriptor<CoopMatch>(predicate: CoopMatch.live))
        return all?.first { $0.levelID == levelID }
    }

    @discardableResult
    /// Idempotent per level: if a match already exists — because she tapped
    /// Start a moment before you did, and it has already arrived — that one is
    /// returned rather than a second being created.
    static func start(levelID: UUID,
                      participants: [String],
                      firstTurn: String,
                      board: BoardSnapshot,
                      in context: ModelContext) -> CoopMatch {
        if let existing = liveMatch(forLevel: levelID, in: context) { return existing }
        let match = CoopMatch(levelID: levelID, participants: participants,
                              turnHolder: firstTurn,
                              boardState: BoardSnapshotCodec.encode(board))
        context.insert(match)
        // **No explicit save.** SwiftData autosaves, and an explicit save from
        // a button action is a synchronous write that, on a phone with iCloud,
        // can be caught behind CloudKit's first schema initialisation — network
        // work on the main thread. Every simulator here has no iCloud account,
        // so that path never ran in testing.
        return match
    }

    /// Records a fling this phone just took.
    ///
    /// - Returns: the turn, or nil when this phone had no right to play — which
    ///   is a refusal rather than an error, because it means the other phone
    ///   got there first and this one hadn't heard yet.
    @discardableResult
    static func takeTurn(clip: FlingClip,
                         by authorID: String,
                         in match: CoopMatch,
                         context: ModelContext) -> CoopTurn? {
        guard CoopTurnRules.mayFling(authorID, in: match),
              let board = BoardSnapshotCodec.decode(match.boardState),
              let settled = CoopBoardRules.settledState(from: clip, startingAt: board)
        else { return nil }

        let turn = CoopTurn(matchID: match.id,
                            index: match.turnIndex + 1,
                            authorID: authorID,
                            clip: FlingClipCodec.encode(clip),
                            resultingState: BoardSnapshotCodec.encode(settled))
        context.insert(turn)
        advance(match, with: turn)
        try? context.save()
        return turn
    }

    /// Folds in a turn that arrived from the other phone.
    ///
    /// - Returns: whether the match moved. `false` covers redelivery and
    ///   out-of-order arrival, neither of which is exceptional — sync does both
    ///   routinely.
    @discardableResult
    static func apply(_ turn: CoopTurn, to match: CoopMatch, context: ModelContext) -> Bool {
        guard CoopTurnRules.verdict(for: turn, in: match) == .accept else { return false }
        advance(match, with: turn)
        try? context.save()
        return true
    }

    /// The turn that should be *watched* next on this phone, if any.
    ///
    /// It is the other player's most recent turn — the one that produced the
    /// board you are about to play against. Derived rather than flagged, so it
    /// cannot drift out of step with the match.
    static func turnToWatch(in match: CoopMatch, viewer: String,
                            context: ModelContext) -> CoopTurn? {
        let matchID = match.id
        let turns = try? context.fetch(FetchDescriptor<CoopTurn>(
            predicate: #Predicate { $0.matchID == matchID && $0.deletedAt == nil }))
        return turns?
            .filter { $0.authorID != viewer && $0.index == match.turnIndex }
            .first
    }

    private static func advance(_ match: CoopMatch, with turn: CoopTurn) {
        match.turnIndex = turn.index
        match.boardState = turn.resultingState
        match.turnHolder = CoopTurnRules.nextHolder(after: turn.authorID, in: match)
        match.updatedAt = .now
    }
}
