import Foundation

/// The three per-level feats (M23) — badges, never currency: the star pool
/// stays M6's single economy, feats are bragging and replay chase.
enum Feat: String, CaseIterable {
    case oneFling, noAbility, cleanSweep
}

enum FeatDetector {
    static func feats(flingsUsed: Int, usedAnyAbility: Bool,
                      destructiblePieces: Int, destroyedPieces: Int) -> Set<Feat> {
        var earned: Set<Feat> = []
        if flingsUsed == 1 { earned.insert(.oneFling) }
        if !usedAnyAbility { earned.insert(.noAbility) }
        // A pieceless level can't award a sweep for destroying nothing.
        if destructiblePieces > 0, destroyedPieces >= destructiblePieces {
            earned.insert(.cleanSweep)
        }
        return earned
    }
}
