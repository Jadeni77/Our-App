import Foundation
import SwiftData

/// What the two of you achieved on a level together. **One row per level, for
/// the couple** — not one each.
///
/// Deliberately not a `MoonshotLevelResult` with `mode: .coop`, even though
/// `PlayMode` has the case. Solo progress is **mirrored** (P23): each phone
/// owns its rows and the other displays them. A co-op clear belongs to the
/// couple *once*, and `SyncCategory` is per type rather than per row — so two
/// phones each writing their own co-op row would count one clear twice in the
/// shared star pool. Same double-counting trap as the harvest problem in the
/// farming design, and the same answer: make the record's identity the thing
/// itself.
@Model
final class CoopLevelResult {
    /// **The level's id, used directly.** Two phones finishing a level
    /// independently therefore create the *same* record and converge on merge,
    /// instead of creating two rows nothing can reconcile.
    var id: UUID = UUID()
    var cleared: Bool = false
    var bestStars: Int = 0
    /// Fewest flings among clearing runs; 0 while uncleared.
    var bestFlings: Int = 0
    var featOneFling: Bool = false
    var featNoAbility: Bool = false
    var featCleanSweep: Bool = false
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    init(levelID: UUID) {
        self.id = levelID
        self.updatedAt = .now
    }

    var levelID: UUID { id }
}

/// Merging two views of the same co-op level.
///
/// **Not last-writer-wins.** LWW would let a worse run overwrite a better one
/// purely by being saved later — she three-stars a level, you two-star it an
/// hour after, and the couple's record goes backwards. Merging toward the best
/// run is also *better behaved* than LWW: max is commutative, associative and
/// idempotent, so both phones converge whatever order things arrive in, with no
/// tiebreak needed at all (contrast P21, where LWW needs one to converge).
enum CoopLedger {
    struct Snapshot: Equatable {
        var cleared = false
        var bestStars = 0
        var bestFlings = 0
        var featOneFling = false
        var featNoAbility = false
        var featCleanSweep = false
    }

    static func merged(_ a: Snapshot, _ b: Snapshot) -> Snapshot {
        Snapshot(
            // Cleared never un-clears: a later failed attempt must not undo a
            // level the two of you already finished.
            cleared: a.cleared || b.cleared,
            bestStars: max(a.bestStars, b.bestStars),
            bestFlings: bestFlings(a, b),
            featOneFling: a.featOneFling || b.featOneFling,
            featNoAbility: a.featNoAbility || b.featNoAbility,
            featCleanSweep: a.featCleanSweep || b.featCleanSweep)
    }

    /// Fewest is best — but 0 means "never cleared", not "cleared in none",
    /// so an uncleared side must not win the minimum.
    private static func bestFlings(_ a: Snapshot, _ b: Snapshot) -> Int {
        switch (a.cleared, b.cleared) {
        case (true, true): min(a.bestFlings, b.bestFlings)
        case (true, false): a.bestFlings
        case (false, true): b.bestFlings
        case (false, false): 0
        }
    }
}

extension CoopLevelResult {
    var snapshot: CoopLedger.Snapshot {
        CoopLedger.Snapshot(cleared: cleared, bestStars: bestStars, bestFlings: bestFlings,
                            featOneFling: featOneFling, featNoAbility: featNoAbility,
                            featCleanSweep: featCleanSweep)
    }

    func apply(_ snapshot: CoopLedger.Snapshot) {
        cleared = snapshot.cleared
        bestStars = snapshot.bestStars
        bestFlings = snapshot.bestFlings
        featOneFling = snapshot.featOneFling
        featNoAbility = snapshot.featNoAbility
        featCleanSweep = snapshot.featCleanSweep
    }

    static var visible: Predicate<CoopLevelResult> {
        #Predicate<CoopLevelResult> { $0.deletedAt == nil }
    }
}
