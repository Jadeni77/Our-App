import Foundation

/// The shared couple reward track (M6): every star anyone earns — solo his,
/// solo hers, co-op ours — pools into one number, and unlocks are *ours*.
/// The pool is derived from result records, never stored, so slice-(d) sync
/// can't produce pool conflicts.

enum TrailID: String, Codable, CaseIterable {
    case stardust, petals, aurora
}

enum RewardGrant: Equatable {
    case trail(TrailID)
    case character(CharacterID)
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
    /// Slice (a) segment; later slices append entries, never reprice (M6).
    static let track: [(threshold: Int, grant: RewardGrant)] = [
        (8, .trail(.stardust)),
        (16, .trail(.petals)),
        (24, .character(.nox)),
        (32, .trail(.aurora)),
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
        guard character == .nox else { return true }
        return grants(pool: pool).contains(.character(.nox))
    }
}
