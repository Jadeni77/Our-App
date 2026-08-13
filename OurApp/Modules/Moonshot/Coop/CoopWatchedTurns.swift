import Foundation

/// Which turns this phone has already watched.
///
/// **Local, never synced.** "Have I seen this?" is a fact about one person in
/// front of one screen, and syncing it would mean her opening the app marked
/// the fling as watched on yours. Contrast the match itself, which is shared
/// because it is a fact about the game rather than about a viewer.
enum CoopWatchedTurns {
    private static func key(_ matchID: UUID) -> String { "coop.watched.\(matchID.uuidString)" }

    static func lastWatchedIndex(_ matchID: UUID, defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: key(matchID))   // 0 when unset, which is correct
    }

    static func markWatched(_ index: Int, of matchID: UUID, defaults: UserDefaults = .standard) {
        // Never goes backwards: an out-of-order arrival must not make you
        // re-watch a fling you have already seen.
        guard index > lastWatchedIndex(matchID, defaults: defaults) else { return }
        defaults.set(index, forKey: key(matchID))
    }

    /// Whether `viewer` still has the current turn to watch.
    static func hasUnwatchedTurn(in match: CoopMatch, viewer: String,
                                 defaults: UserDefaults = .standard) -> Bool {
        match.turnIndex > lastWatchedIndex(match.id, defaults: defaults)
            && match.turnHolder == viewer      // it came *to* you, so it was hers
            && match.turnIndex > 0
    }
}
