import Foundation

/// Who may fling, and whether a turn that has arrived is allowed to count.
///
/// Pure, because this is the part that decides whether the game is fair, and
/// because the interesting cases — a turn arriving twice, two turns claiming
/// one index, a turn from someone who isn't playing — are all reachable in
/// tests and none of them are reachable by tapping.
enum CoopTurnRules {
    enum Verdict: Equatable {
        case accept
        /// Already applied. Arriving twice is normal, not an error: sync
        /// re-delivers, and the same turn must not advance the match twice.
        case alreadyApplied
        /// Someone played out of order — the one genuine conflict.
        case outOfOrder(expected: Int)
        case notYourTurn
        case notAParticipant
        case matchFinished
    }

    /// Whether `authorID` may start a fling right now.
    ///
    /// **The turn token is the whole permission model.** The owner's rule: you
    /// can only fling when you hold the turn, which is what makes an offline
    /// player harmless — they were never entitled to a turn they could take
    /// against a board that had moved on.
    static func mayFling(_ authorID: String, in match: CoopMatch) -> Bool {
        match.finishedAt == nil
            && match.participants.contains(authorID)
            && match.turnHolder == authorID
    }

    /// Whether an arriving turn should be applied to the match.
    static func verdict(for turn: CoopTurn, in match: CoopMatch) -> Verdict {
        guard match.finishedAt == nil else { return .matchFinished }
        guard match.participants.contains(turn.authorID) else { return .notAParticipant }
        guard turn.index != match.turnIndex else { return .alreadyApplied }
        guard turn.index == match.turnIndex + 1 else {
            return .outOfOrder(expected: match.turnIndex + 1)
        }
        guard match.turnHolder == turn.authorID else { return .notYourTurn }
        return .accept
    }

    /// Who takes the opening shot.
    ///
    /// **Decided by the ids, not by who tapped Start first.** Both phones
    /// compute the same answer from the same two strings with nothing to
    /// negotiate — where "whoever tapped first" is a race that, without sync in
    /// between, has both of them believing they won.
    static func firstTurn(among participants: [String]) -> String {
        participants.sorted().first ?? ""
    }

    /// The other participant. Two players, so "next" is "not you".
    static func nextHolder(after authorID: String, in match: CoopMatch) -> String {
        match.participants.first { $0 != authorID } ?? authorID
    }
}
