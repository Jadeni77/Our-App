import Foundation

/// The bundled campaign: `level-NN.json` resources decoded into the shared
/// level format, plus the unlock rule (per-partner linear progression).
struct CampaignCatalog {
    let levels: [MoonshotLevel]

    /// The app-bundle campaign, decoded once per process — views use this;
    /// tests exercise `load(from:)` directly.
    static let bundled = CampaignCatalog.load()

    /// Fail soft (principle 7): an unreadable or undecodable level file is
    /// skipped, never fatal — a broken level can't brick the campaign.
    /// Synchronized folder groups flatten resources into the bundle root, so
    /// the filename prefix — not a subdirectory — is the lookup contract.
    static func load(from bundle: Bundle = .main) -> CampaignCatalog {
        let urls = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("level-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let decoder = MoonshotLevel.decoder()
        let levels = urls.compactMap { url -> MoonshotLevel? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(MoonshotLevel.self, from: data)
        }
        return CampaignCatalog(levels: levels)
    }

    /// Level 1 is always open; level N needs level N−1 cleared *by this
    /// partner* — solo or (slice d) assist, matching M12's "assist unlocks".
    func isUnlocked(index: Int, snapshots: [LevelResultSnapshot], partnerID: String) -> Bool {
        guard index > 0 else { return true }
        guard levels.indices.contains(index) else { return false }
        let previousID = levels[index - 1].id
        return snapshots.contains {
            $0.partnerID == partnerID && $0.levelID == previousID
                && $0.cleared && ($0.mode == .solo || $0.mode == .assist)
        }
    }

    // MARK: Worlds (a2, M24)

    /// Highest world number present (worlds are authored contiguously from 1).
    var worldCount: Int {
        levels.map(\.worldNumber).max() ?? 0
    }

    /// A world's levels in catalog order.
    func levels(inWorld world: Int) -> [MoonshotLevel] {
        levels.filter { $0.worldNumber == world }
    }

    /// The world gate IS the linear rule at the world boundary: world N is
    /// open exactly when its first level is unlocked (world N−1's final
    /// level cleared). No second gating mechanism to keep consistent.
    func isWorldUnlocked(_ world: Int, snapshots: [LevelResultSnapshot], partnerID: String) -> Bool {
        guard world > 1 else { return true }
        guard let first = levels(inWorld: world).first,
              let index = globalIndex(of: first) else { return false }
        return isUnlocked(index: index, snapshots: snapshots, partnerID: partnerID)
    }

    /// Index into the flat `levels` order (what `MoonshotGameView` navigates by).
    func globalIndex(of level: MoonshotLevel) -> Int? {
        levels.firstIndex { $0.id == level.id }
    }

    /// Where "Continue" points (M27): the first level this partner hasn't
    /// cleared solo but CAN play. Nil once the campaign is finished.
    func nextPlayableIndex(snapshots: [LevelResultSnapshot], partnerID: String) -> Int? {
        levels.indices.first { index in
            let cleared = snapshots.contains {
                $0.partnerID == partnerID && $0.levelID == levels[index].id
                    && $0.mode == .solo && $0.cleared
            }
            return !cleared && isUnlocked(index: index, snapshots: snapshots, partnerID: partnerID)
        }
    }
}
