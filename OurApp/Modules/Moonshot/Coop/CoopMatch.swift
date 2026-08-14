import Foundation
import SwiftData

/// One campaign level being played together, across distance.
///
/// Turn-based rather than simultaneous, because a fling is already a discrete
/// act and the game has always alternated strictly (M9) — and because two people
/// flinging at once from different cities needs a live channel the async layer
/// deliberately doesn't require. It works while she is asleep.
@Model
final class CoopMatch {
    var id: UUID = UUID()
    var levelID: UUID = UUID()
    /// Exactly two `authorID`s (P18). Stored rather than derived so a match
    /// still makes sense on a phone that has never met the other player.
    var participants: [String] = []
    /// Whose fling it is. **The only thing that grants the right to play.**
    var turnHolder: String = ""
    /// Strictly increasing. A turn is valid only at `turnIndex + 1`, which is
    /// what makes "both thought it was their turn" resolvable rather than a
    /// silent double-play.
    var turnIndex: Int = 0
    /// Opaque to this layer: the engine owns its shape. **Authoritative** — the
    /// clip is what you watch, this is what the next turn starts from.
    var boardState: Data = Data()
    var finishedAt: Date?
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    /// **The id *is* the level id.** Two phones starting the same level
    /// independently must produce the *same* record, or each creates its own
    /// match, both sync, and each device then picks whichever it finds first —
    /// usually the other's, where the turn belongs to the other person. Both
    /// sides sit on "Waiting for her" forever.
    ///
    /// Same trap, same answer as `CoopLevelResult` (P23's ledger): make the
    /// record's identity the thing itself. That one was fixed and this one was
    /// not, which is how it shipped.
    init(levelID: UUID, participants: [String], turnHolder: String, boardState: Data = Data()) {
        self.id = levelID
        self.levelID = levelID
        self.participants = participants
        self.turnHolder = turnHolder
        self.boardState = boardState
        self.updatedAt = .now
    }
}

/// One fling. **Append-only**: a turn is never edited, so turns never conflict.
///
/// That is deliberate. It leaves `CoopMatch` as the only record with a merge
/// policy; everything else is a union, which is the cheapest kind of sync there
/// is.
@Model
final class CoopTurn {
    var id: UUID = UUID()
    var matchID: UUID = UUID()
    /// The index this turn produced — matches the `turnIndex` it advanced to.
    var index: Int = 0
    var authorID: String = ""
    /// The recording. **May be empty**, and the turn still counts: losing the
    /// show must never mean losing the game.
    var clip: Data = Data()
    var resultingState: Data = Data()
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    init(matchID: UUID, index: Int, authorID: String,
         clip: Data = Data(), resultingState: Data = Data()) {
        self.id = UUID()
        self.matchID = matchID
        self.index = index
        self.authorID = authorID
        self.clip = clip
        self.resultingState = resultingState
        self.updatedAt = .now
    }
}

extension CoopMatch {
    static var live: Predicate<CoopMatch> {
        #Predicate<CoopMatch> { $0.deletedAt == nil && $0.finishedAt == nil }
    }
}
