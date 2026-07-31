import Foundation
import Testing
@testable import OurApp

struct CampaignCatalogTests {
    @Test func catalogLoadsBundledLevelsInOrder() {
        let catalog = CampaignCatalog.load()
        #expect(catalog.levels.count >= 1)                    // becomes == 12 with the campaign PR
        #expect(catalog.levels[0].kind == .campaign)
        #expect(catalog.levels[0].par == 2)
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
