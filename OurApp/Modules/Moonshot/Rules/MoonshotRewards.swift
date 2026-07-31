import Foundation

/// The shared couple reward track (M6): every star anyone earns — solo his,
/// solo hers, co-op ours — pools into one number, and unlocks are *ours*.
/// The pool is derived from result records, never stored, so slice-(d) sync
/// can't produce pool conflicts.

enum TrailID: String, Codable, CaseIterable {
    case stardust, petals, aurora, nebula
}

enum ConstellationTheme: String, Codable, CaseIterable {
    case dawn
}

enum SlingshotSkin: String, Codable, CaseIterable {
    case golden
}

enum RewardGrant: Equatable {
    case trail(TrailID)
    case character(CharacterID)
    case theme(ConstellationTheme)
    case skin(SlingshotSkin)
}

/// A SwiftData-free view of a result row, so Rules stays pure and testable.
struct LevelResultSnapshot: Equatable {
    let partnerID: String
    let levelID: UUID
    let mode: PlayMode
    let cleared: Bool
    let bestStars: Int
}

enum MoonshotRewards {
    /// Rows only ever append, never reprice (M6). Slice (a) opened 8–32;
    /// slice (a2) extends to 96 — the 36-level solo ceiling is 108★.
    static let track: [(threshold: Int, grant: RewardGrant)] = [
        (8, .trail(.stardust)),
        (16, .trail(.petals)),
        (24, .character(.nox)),
        (32, .trail(.aurora)),
        (45, .trail(.nebula)),
        (60, .character(.misty)),
        (78, .theme(.dawn)),
        (96, .skin(.golden)),
    ]

    /// Best solo stars per (partner, level) + best co-op stars per level.
    /// Assist results bank nothing (M12) — filtered here as well as zeroed
    /// at record time, so farming is impossible even if bad data sneaks in.
    static func starPool(_ results: [LevelResultSnapshot]) -> Int {
        var bestSolo: [String: Int] = [:]      // "partnerID|levelID" → stars
        var bestCoop: [UUID: Int] = [:]
        for result in results {
            switch result.mode {
            case .solo:
                let key = "\(result.partnerID)|\(result.levelID.uuidString)"
                bestSolo[key] = max(bestSolo[key] ?? 0, result.bestStars)
            case .coop:
                bestCoop[result.levelID] = max(bestCoop[result.levelID] ?? 0, result.bestStars)
            case .assist:
                continue
            }
        }
        return bestSolo.values.reduce(0, +) + bestCoop.values.reduce(0, +)
    }

    static func grants(pool: Int) -> [RewardGrant] {
        track.filter { pool >= $0.threshold }.map(\.grant)
    }

    static func isUnlocked(_ character: CharacterID, pool: Int) -> Bool {
        switch character {
        case .nox, .misty:
            grants(pool: pool).contains(.character(character))
        case .mochi, .zip, .twinkle:
            // Exhaustive on purpose: a future earned character must make a
            // conscious appearance here, not inherit "always unlocked".
            true
        }
    }
}
