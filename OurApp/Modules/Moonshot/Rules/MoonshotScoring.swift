/// Golf-style par stars (M5): one designer-set number per level, no score
/// thresholds to playtest — the playtest team is two people.
enum MoonshotScoring {
    /// 0 when not cleared; 3 at or under par; 2 at par+1; 1 otherwise.
    static func stars(cleared: Bool, flingsUsed: Int, par: Int) -> Int {
        guard cleared else { return 0 }
        if flingsUsed <= par { return 3 }
        if flingsUsed == par + 1 { return 2 }
        return 1
    }
}
