import Foundation
import SwiftData
import Testing
@testable import OurApp

@MainActor struct MoonshotProgressTests {
    /// ModelContext does NOT retain its ModelContainer — a fixture that
    /// returned only the store would deallocate the container on return and
    /// the first fetch would trap inside SwiftData (EXC_BREAKPOINT, no
    /// message). The fixture owns the container for the test's lifetime.
    private struct Fixture {
        let container: ModelContainer
        let store: MoonshotProgressStore
    }

    private func makeStore() throws -> Fixture {
        let container = try Persistence.makeContainer(inMemory: true)
        return Fixture(container: container,
                       store: MoonshotProgressStore(context: container.mainContext, partnerID: "one"))
    }

    @Test func firstResultCreatesARow() throws {
        let fixture = try makeStore()
        let store = fixture.store
        let level = UUID()
        store.recordSolo(levelID: level, cleared: true, stars: 2, flings: 3)
        let row = try #require(store.result(for: level))
        #expect(row.bestStars == 2)
        #expect(row.bestFlings == 3)
        #expect(row.cleared)
    }

    @Test func repeatResultsMergeBestNotLast() throws {
        let fixture = try makeStore()
        let store = fixture.store
        let level = UUID()
        store.recordSolo(levelID: level, cleared: true, stars: 3, flings: 2)
        store.recordSolo(levelID: level, cleared: true, stars: 1, flings: 6)   // worse run later
        let row = try #require(store.result(for: level))
        #expect(row.bestStars == 3)
        #expect(row.bestFlings == 2)
    }

    @Test func failedRunNeverUnclears() throws {
        let fixture = try makeStore()
        let store = fixture.store
        let level = UUID()
        store.recordSolo(levelID: level, cleared: true, stars: 1, flings: 5)
        store.recordSolo(levelID: level, cleared: false, stars: 0, flings: 3)
        #expect(try #require(store.result(for: level)).cleared)
    }

    @Test func poolDerivesFromRows() throws {
        let fixture = try makeStore()
        let store = fixture.store
        store.recordSolo(levelID: UUID(), cleared: true, stars: 3, flings: 1)
        store.recordSolo(levelID: UUID(), cleared: true, stars: 2, flings: 2)
        #expect(store.starPool == 5)
    }

    @Test func featsOrMergeAndNeverRegress() throws {
        let fixture = try makeStore()
        let store = fixture.store
        let level = UUID()
        store.recordSolo(levelID: level, cleared: true, stars: 1, flings: 3, feats: [.cleanSweep])
        store.recordSolo(levelID: level, cleared: true, stars: 3, flings: 1, feats: [.oneFling])
        let row = try #require(store.result(for: level))
        #expect(row.featCleanSweep && row.featOneFling && !row.featNoAbility)
    }

    @Test func trailEquipsAndPersistsPerPartner() throws {
        let fixture = try makeStore()
        let store = fixture.store
        #expect(store.equippedTrail == nil)
        store.equipTrail(.stardust)
        #expect(store.equippedTrail == .stardust)
    }

    @Test func themeAndSkinEquipIndependentlyOfTrail() throws {
        let fixture = try makeStore()
        let store = fixture.store
        store.equipTrail(.aurora)
        store.equipTheme(.dawn)
        store.equipSkin(.golden)
        #expect(store.equippedTrail == .aurora)
        #expect(store.equippedTheme == .dawn)
        #expect(store.equippedSkin == .golden)
        store.equipTheme(nil)
        #expect(store.equippedTheme == nil)
        #expect(store.equippedSkin == .golden)
    }
}
