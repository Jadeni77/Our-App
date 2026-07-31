import Foundation
import Testing
@testable import OurApp

struct CampaignCatalogTests {
    @Test func everyPresentWorldShipsExactlyTwelveLevels() {
        let catalog = CampaignCatalog.load()
        #expect(Set(catalog.levels.map(\.id)).count == catalog.levels.count)   // unique ids
        for world in 1...catalog.worldCount {
            let levels = catalog.levels(inWorld: world)
            #expect(levels.count == 12, "world \(world) must ship exactly 12 levels")
            for (index, level) in levels.enumerated() {
                #expect(level.kind == .campaign)
                #expect(!level.glooms.isEmpty, "W\(world) L\(index + 1) has no glooms")
                #expect(level.par >= 1 && level.par <= level.queue.count,
                        "W\(world) L\(index + 1) par must be honest against its queue")
                for piece in level.pieces {
                    #expect(piece.x > MoonshotTuning.slingshotX + 100,
                            "W\(world) L\(index + 1) builds on top of the slingshot")
                }
            }
        }
    }

    @Test func earlyLevelsTeachBeforeTheyMix() {
        // The teaching arc (M4): W1 1–3 mochi-only, 4 introduces zip, 7 twinkle.
        let catalog = CampaignCatalog.load()
        let world1 = catalog.levels(inWorld: 1)
        guard world1.count == 12 else { return }
        for level in world1[0...2] {
            #expect(Set(level.queue) == [.mochi])
        }
        #expect(world1[3].queue.contains(.zip))
        #expect(world1[6].queue.contains(.twinkle))
        // Nox appears in no W1/W2 queue — his requirement debuts in W3 (M21),
        // where entry mathematically guarantees his 24★ unlock.
        for level in catalog.levels where level.worldNumber < 3 {
            #expect(!level.queue.contains(.nox))
        }
    }

    @Test func firstLevelIsAlwaysUnlocked() {
        let catalog = CampaignCatalog.load()
        #expect(catalog.isUnlocked(index: 0, snapshots: [], partnerID: "one"))
    }

    // The unlock rule is tested against synthetic levels so coverage doesn't
    // wait for the full bundled campaign (review finding on this PR).
    private func makeCatalog(worlds: [Int] = [1, 1]) -> CampaignCatalog {
        func level(world: Int) -> MoonshotLevel {
            MoonshotLevel(schemaVersion: 1, id: UUID(), kind: .campaign, authorID: nil,
                          createdAt: .now, updatedAt: .now, deletedAt: nil, title: nil,
                          par: 1, queue: [.mochi],
                          buildZone: .init(x: 500, y: 0, width: 320, height: 340),
                          pieces: [], glooms: [.init(x: 600, y: 16)],
                          world: world == 1 ? nil : world)
        }
        return CampaignCatalog(levels: worlds.map(level(world:)))
    }

    @Test func worldQueriesGroupAndCount() {
        let catalog = makeCatalog(worlds: [1, 1, 2, 2, 3])
        #expect(catalog.worldCount == 3)
        #expect(catalog.levels(inWorld: 2).count == 2)
        #expect(catalog.levels(inWorld: 1).count == 2)
    }

    @Test func worldUnlockIsTheLinearRuleAtTheWorldBoundary() {
        let catalog = makeCatalog(worlds: [1, 1, 2])
        #expect(catalog.isWorldUnlocked(1, snapshots: [], partnerID: "one"))
        #expect(!catalog.isWorldUnlocked(2, snapshots: [], partnerID: "one"))
        let lastOfW1 = catalog.levels(inWorld: 1).last!
        let cleared = LevelResultSnapshot(partnerID: "one", levelID: lastOfW1.id,
                                          mode: .solo, cleared: true, bestStars: 1)
        #expect(catalog.isWorldUnlocked(2, snapshots: [cleared], partnerID: "one"))
    }

    @Test func globalIndexRoundTrips() {
        let catalog = makeCatalog(worlds: [1, 1, 2])
        let level = catalog.levels(inWorld: 2)[0]
        #expect(catalog.globalIndex(of: level) == 2)
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
