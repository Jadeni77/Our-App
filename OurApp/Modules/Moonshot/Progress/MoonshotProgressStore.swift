import Foundation
import SwiftData

/// Moonshot's window onto the core container (module contract: own namespace,
/// shared persistence). Reads and writes result rows for one partner — the
/// device owner in slice (a) — and derives the couple star pool.
@MainActor
final class MoonshotProgressStore {
    /// Slice (a): solo results credit the device owner. The key becomes a
    /// real settings-sheet picker when a second identity first matters
    /// (slice b pass-the-phone); until then it defaults to partner one.
    /// nonisolated so it can serve as a default argument (those evaluate
    /// outside the class's MainActor isolation).
    nonisolated static var devicePartnerID: String {
        UserDefaults.standard.string(forKey: "couple.devicePartner") ?? Partner.one.rawValue
    }

    let partnerID: String
    private let context: ModelContext

    init(context: ModelContext, partnerID: String = MoonshotProgressStore.devicePartnerID) {
        self.context = context
        self.partnerID = partnerID
    }

    /// Merge toward the best run: `cleared` never un-clears, stars max,
    /// flings min among clearing runs.
    @discardableResult
    func recordSolo(levelID: UUID, cleared: Bool, stars: Int, flings: Int,
                    feats: Set<Feat> = []) -> MoonshotLevelResult {
        let row = result(for: levelID) ?? {
            let fresh = MoonshotLevelResult(partnerID: partnerID, levelID: levelID, mode: .solo,
                                            cleared: false, bestStars: 0, bestFlings: 0)
            context.insert(fresh)
            return fresh
        }()
        if cleared {
            row.bestFlings = row.cleared ? min(row.bestFlings, flings) : flings
            row.cleared = true
            row.bestStars = max(row.bestStars, stars)
            row.featOneFling = row.featOneFling || feats.contains(.oneFling)
            row.featNoAbility = row.featNoAbility || feats.contains(.noAbility)
            row.featCleanSweep = row.featCleanSweep || feats.contains(.cleanSweep)
        }
        row.updatedAt = .now
        try? context.save()
        return row
    }

    /// This partner's solo row for a level, if any.
    func result(for levelID: UUID) -> MoonshotLevelResult? {
        let mode = PlayMode.solo.rawValue
        let partner = partnerID
        let descriptor = FetchDescriptor<MoonshotLevelResult>(predicate: #Predicate {
            $0.levelID == levelID && $0.partnerID == partner && $0.modeRaw == mode
        })
        return (try? context.fetch(descriptor))?.first
    }

    /// Every result row (all partners, all modes) as Rules-layer snapshots.
    func snapshots() -> [LevelResultSnapshot] {
        let rows = (try? context.fetch(FetchDescriptor<MoonshotLevelResult>())) ?? []
        return rows.map(\.snapshot)
    }

    var starPool: Int {
        MoonshotRewards.starPool(snapshots())
    }

    var equippedTrail: TrailID? {
        cosmeticRow()?.trail
    }

    func equipTrail(_ trail: TrailID?) {
        ensureCosmeticRow().trail = trail
        try? context.save()
    }

    var equippedTheme: ConstellationTheme? {
        cosmeticRow()?.theme
    }

    func equipTheme(_ theme: ConstellationTheme?) {
        ensureCosmeticRow().theme = theme
        try? context.save()
    }

    var equippedSkin: SlingshotSkin? {
        cosmeticRow()?.skin
    }

    func equipSkin(_ skin: SlingshotSkin?) {
        ensureCosmeticRow().skin = skin
        try? context.save()
    }

    // MARK: Moondust wallet (M31)

    /// The couple's balance: every partner's rows summed — one wallet.
    func moondustBalance() -> Int {
        let rows = (try? context.fetch(FetchDescriptor<MoonshotMoondustEntry>())) ?? []
        return rows.reduce(0) { $0 + $1.amount }
    }

    func addMoondust(_ amount: Int, reason: String) {
        context.insert(MoonshotMoondustEntry(partnerID: partnerID, amount: amount, reason: reason))
        try? context.save()
    }

    /// A spend is a negative row AFTER the guard — the append-only ledger
    /// never goes below zero and union-merge can't create debt.
    @discardableResult
    func spendMoondust(_ amount: Int, reason: String) -> Bool {
        guard moondustBalance() >= amount else { return false }
        context.insert(MoonshotMoondustEntry(partnerID: partnerID, amount: -amount, reason: reason))
        try? context.save()
        return true
    }

    // MARK: Coach ledger (M25)

    /// Storage keys of every coach moment this partner has seen.
    func seenCoachKeys() -> Set<String> {
        let partner = partnerID
        let descriptor = FetchDescriptor<MoonshotCoachSeen>(predicate: #Predicate {
            $0.partnerID == partner
        })
        return Set((try? context.fetch(descriptor))?.map(\.momentKey) ?? [])
    }

    /// Append-only, idempotent — a double-mark leaves one row.
    func markCoachSeen(_ moment: CoachMoment) {
        guard !seenCoachKeys().contains(moment.storageKey) else { return }
        context.insert(MoonshotCoachSeen(partnerID: partnerID, momentKey: moment.storageKey))
        try? context.save()
    }

    /// DEBUG re-teaching aid (`-moonshotCoachReset`) — this partner only.
    func resetCoach() {
        let partner = partnerID
        let descriptor = FetchDescriptor<MoonshotCoachSeen>(predicate: #Predicate {
            $0.partnerID == partner
        })
        for row in (try? context.fetch(descriptor)) ?? [] { context.delete(row) }
        try? context.save()
    }

    private func ensureCosmeticRow() -> MoonshotCosmeticSetting {
        cosmeticRow() ?? {
            let fresh = MoonshotCosmeticSetting(partnerID: partnerID, trail: nil)
            context.insert(fresh)
            return fresh
        }()
    }

    private func cosmeticRow() -> MoonshotCosmeticSetting? {
        let partner = partnerID
        let descriptor = FetchDescriptor<MoonshotCosmeticSetting>(predicate: #Predicate {
            $0.partnerID == partner
        })
        return (try? context.fetch(descriptor))?.first
    }
}
