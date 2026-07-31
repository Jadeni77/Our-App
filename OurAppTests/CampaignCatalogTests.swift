import Foundation
import Testing
@testable import OurApp

struct CampaignCatalogTests {
    @Test func campaignShipsExactlyTwelveLevels() {
        let catalog = CampaignCatalog.load()
        #expect(catalog.levels.count == 12)
        #expect(Set(catalog.levels.map(\.id)).count == 12)    // unique ids
        for (index, level) in catalog.levels.enumerated() {
            #expect(level.kind == .campaign)
            #expect(!level.glooms.isEmpty, "level \(index + 1) has no glooms")
            #expect(level.par >= 1 && level.par <= level.queue.count,
                    "level \(index + 1) par must be honest against its queue")
            for piece in level.pieces {
                #expect(piece.x > MoonshotTuning.slingshotX + 100,
                        "level \(index + 1) builds on top of the slingshot")
            }
        }
    }

    @Test func earlyLevelsTeachBeforeTheyMix() {
        // The teaching arc (M4): 1–3 mochi-only, 4 introduces zip, 7 twinkle.
        let levels = CampaignCatalog.load().levels
        guard levels.count == 12 else { return }
        for level in levels[0...2] {
            #expect(Set(level.queue) == [.mochi])
        }
        #expect(levels[3].queue.contains(.zip))
        #expect(levels[6].queue.contains(.twinkle))
        // Nox never appears in a campaign queue — he's a choice, not a requirement.
        for level in levels {
            #expect(!level.queue.contains(.nox))
        }
    }

    @Test func firstLevelIsAlwaysUnlocked() {
        let catalog = CampaignCatalog.load()
        #expect(catalog.isUnlocked(index: 0, snapshots: [], partnerID: "one"))
    }

    // The unlock rule is tested against synthetic levels so coverage doesn't
    // wait for the full bundled campaign (review finding on this PR).
    private func makeCatalog() -> CampaignCatalog {
        func level() -> MoonshotLevel {
            MoonshotLevel(schemaVersion: 1, id: UUID(), kind: .campaign, authorID: nil,
                          createdAt: .now, updatedAt: .now, deletedAt: nil, title: nil,
                          par: 1, queue: [.mochi],
                          buildZone: .init(x: 500, y: 0, width: 320, height: 340),
                          pieces: [], glooms: [.init(x: 600, y: 16)])
        }
        return CampaignCatalog(levels: [level(), level()])
    }

    @Test func nextLevelNeedsPreviousClearedByThisPartner() {
        let catalog = makeCatalog()
        let prev = catalog.levels[0].id
        let mine = LevelResultSnapshot(partnerID: "one", levelID: prev, mode: .solo, cleared: true, bestStars: 1)
        let hers = LevelResultSnapshot(partnerID: "two", levelID: prev, mode: .solo, cleared: true, bestStars: 3)
        #expect(catalog.isUnlocked(index: 1, snapshots: [mine], partnerID: "one"))
        #expect(!catalog.isUnlocked(index: 1, snapshots: [hers], partnerID: "one"))
    }

    @Test func failedOrCoopRunsDoNotUnlockButAssistDoes() {
        let catalog = makeCatalog()
        let prev = catalog.levels[0].id
        let failed = LevelResultSnapshot(partnerID: "one", levelID: prev, mode: .solo, cleared: false, bestStars: 0)
        let coop = LevelResultSnapshot(partnerID: "one", levelID: prev, mode: .coop, cleared: true, bestStars: 2)
        let assist = LevelResultSnapshot(partnerID: "one", levelID: prev, mode: .assist, cleared: true, bestStars: 0)
        #expect(!catalog.isUnlocked(index: 1, snapshots: [failed], partnerID: "one"))
        #expect(!catalog.isUnlocked(index: 1, snapshots: [coop], partnerID: "one"))
        #expect(catalog.isUnlocked(index: 1, snapshots: [assist], partnerID: "one"))
    }

    @Test func indexPastTheCampaignIsNeverUnlocked() {
        let catalog = makeCatalog()
        #expect(!catalog.isUnlocked(index: 5, snapshots: [], partnerID: "one"))
    }
}
