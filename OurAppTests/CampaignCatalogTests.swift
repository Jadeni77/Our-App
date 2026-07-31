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

    @Test func nextLevelNeedsPreviousClearedByThisPartner() {
        let catalog = CampaignCatalog.load()
        guard catalog.levels.count >= 2 else { return }       // guard drops with the campaign PR
        let prev = catalog.levels[0].id
        let mine = LevelResultSnapshot(partnerID: "one", levelID: prev, mode: .solo, cleared: true, bestStars: 1)
        let hers = LevelResultSnapshot(partnerID: "two", levelID: prev, mode: .solo, cleared: true, bestStars: 3)
        #expect(catalog.isUnlocked(index: 1, snapshots: [mine], partnerID: "one"))
        #expect(!catalog.isUnlocked(index: 1, snapshots: [hers], partnerID: "one"))
    }
}
