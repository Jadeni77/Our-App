import Foundation
import SwiftData

/// One row per (partner, level, mode), merged toward the best run — an
/// append/max shape on purpose (§7 record hygiene): when slice-(d) sync
/// lands, two phones' rows union with a max-merge instead of conflicting.
@Model
final class MoonshotLevelResult {
    @Attribute(.unique) var id: UUID
    var partnerID: String
    var levelID: UUID
    var modeRaw: String
    var cleared: Bool
    var bestStars: Int
    var bestFlings: Int
    /// Slice (d): the helper's partner id on "cleared — assist" rows (M12).
    var assistedBy: String?
    var updatedAt: Date

    init(partnerID: String, levelID: UUID, mode: PlayMode, cleared: Bool, bestStars: Int, bestFlings: Int) {
        id = UUID()
        self.partnerID = partnerID
        self.levelID = levelID
        modeRaw = mode.rawValue
        self.cleared = cleared
        self.bestStars = bestStars
        self.bestFlings = bestFlings
        assistedBy = nil
        updatedAt = .now
    }

    var mode: PlayMode { PlayMode(rawValue: modeRaw) ?? .solo }

    var snapshot: LevelResultSnapshot {
        LevelResultSnapshot(partnerID: partnerID, levelID: levelID, mode: mode,
                            cleared: cleared, bestStars: bestStars)
    }
}

/// Which flight trail a partner has equipped — a last-writer-wins settings
/// record (one per partner), unlike the append/max results above.
@Model
final class MoonshotCosmeticSetting {
    @Attribute(.unique) var partnerID: String
    var trailRaw: String?
    var updatedAt: Date

    init(partnerID: String, trail: TrailID?) {
        self.partnerID = partnerID
        trailRaw = trail?.rawValue
        updatedAt = .now
    }

    var trail: TrailID? {
        get { trailRaw.flatMap(TrailID.init(rawValue:)) }
        set {
            trailRaw = newValue?.rawValue
            updatedAt = .now
        }
    }
}
