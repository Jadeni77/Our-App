import Foundation
import SwiftData

/// One row per (partner, level, mode), merged toward the best run — an
/// append/max shape on purpose (§7 record hygiene): when slice-(d) sync
/// lands, two phones' rows union with a max-merge instead of conflicting.
@Model
final class MoonshotLevelResult {
    // No `@Attribute(.unique)`: SwiftData's CloudKit mirroring rejects it
    // outright, and under mirroring a uniqueness constraint turns the other
    // phone's row into a collision rather than a separate record (§7).
    var id: UUID
    var partnerID: String
    var levelID: UUID
    var modeRaw: String
    var cleared: Bool
    var bestStars: Int
    var bestFlings: Int
    /// Slice (d): the helper's partner id on "cleared — assist" rows (M12).
    var assistedBy: String?
    var updatedAt: Date
    /// Feat badges (M23) — or-merged like `cleared`; never currency.
    var featOneFling: Bool = false
    var featNoAbility: Bool = false
    var featCleanSweep: Bool = false

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
    // Was `@Attribute(.unique)`, which allowed exactly one row per partner id
    // in the entire store. Wrong twice over: mirroring rejects unique
    // constraints, and the other phone's row is a *different* record rather
    // than a duplicate of ours.
    var partnerID: String
    var trailRaw: String?
    var themeRaw: String?
    var skinRaw: String?
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

    var theme: ConstellationTheme? {
        get { themeRaw.flatMap(ConstellationTheme.init(rawValue:)) }
        set {
            themeRaw = newValue?.rawValue
            updatedAt = .now
        }
    }

    var skin: SlingshotSkin? {
        get { skinRaw.flatMap(SlingshotSkin.init(rawValue:)) }
        set {
            skinRaw = newValue?.rawValue
            updatedAt = .now
        }
    }
}
