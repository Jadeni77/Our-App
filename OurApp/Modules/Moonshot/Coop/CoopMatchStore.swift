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

    /// Any match for a level, finished or not.
    ///
    /// Separate from `liveMatch` because "is there a game to play" and "does a
    /// row already exist" are different questions, and answering the second
    /// with the first is how a duplicate gets inserted.
    static func anyMatch(forLevel levelID: UUID, in context: ModelContext) -> CoopMatch? {
        let all = try? context.fetch(FetchDescriptor<CoopMatch>(
            predicate: #Predicate<CoopMatch> { $0.deletedAt == nil }))
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
        // Matched on *any* existing match, not just a live one. A match's id is
        // its level's id, so inserting a second row for a level you have
        // already cleared together would put two rows with one identity in the
        // store, and every merge afterwards would pick between them arbitrarily.
        if let existing = anyMatch(forLevel: levelID, in: context) { return existing }
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

    /// Finishes a match whose board is already clear.
    ///
    /// `advance` is where a win is normally noticed, but it only runs when a
    /// turn moves the match — so a match that reached a cleared board by any
    /// other route, including one left behind by a build that couldn't finish a
    /// match at all, would sit on "waiting" forever. Checking the board on load
    /// costs one decode and means the ending is a property of the board rather
    /// than of which code ran when.
    @discardableResult
    static func reconcile(_ match: CoopMatch, context: ModelContext) -> Bool {
        guard match.finishedAt == nil,
              BoardSnapshotCodec.decode(match.boardState)?.isCleared == true
        else { return false }
        match.finishedAt = .now
        match.updatedAt = .now
        try? context.save()
        return true
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

    /// The board a turn was played against — what its clip was recorded on top
    /// of, and therefore the only board it can be replayed over.
    ///
    /// `match.boardState` is the board *after* the turn, so handing that to the
    /// replay meant every piece the shot destroyed was already gone before the
    /// clip started. You saw the survivors move a little at the end and nothing
    /// of the shot itself.
    ///
    /// Derived from the previous turn rather than stored: one board held in two
    /// places is two boards waiting to disagree.
    static func startingBoard(for turn: CoopTurn,
                              level: MoonshotLevel,
                              context: ModelContext) -> BoardSnapshot? {
        let matchID = turn.matchID
        let previousIndex = turn.index - 1
        let earlier = try? context.fetch(FetchDescriptor<CoopTurn>(
            predicate: #Predicate { $0.matchID == matchID && $0.index == previousIndex }))
        if let previous = earlier?.first {
            return BoardSnapshotCodec.decode(previous.resultingState)
        }
        // The first turn of a match starts from the level as authored.
        return BoardSnapshot(startOf: level)
    }

    private static func advance(_ match: CoopMatch, with turn: CoopTurn) {
        match.turnIndex = turn.index
        match.boardState = turn.resultingState
        match.turnHolder = CoopTurnRules.nextHolder(after: turn.authorID, in: match)
        // **A cleared board ends the match, on both phones, unprompted.** Every
        // path that moves a match runs through here — the fling you took and
        // the clip you watched alike — so each phone derives the ending from
        // the same resulting state. Nothing has to be sent, and there is no
        // window where one phone thinks the game is still on.
        //
        // Until this existed nothing in the app ever wrote `finishedAt`, so
        // winning simply handed the cleared level to the other player and both
        // phones sat waiting on a game that was already over.
        if match.finishedAt == nil,
           BoardSnapshotCodec.decode(turn.resultingState)?.isCleared == true {
            match.finishedAt = .now
        }
        match.updatedAt = .now
    }
}
