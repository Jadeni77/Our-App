import Foundation
import Testing
@testable import OurApp

struct GamesLayoutTests {
    @Test func defaultLayoutListsAllModulesLooseInOrder() {
        let layout = GamesLayout.default(moduleIDs: ["food-decision", "sample-dice"])
        #expect(layout.version == GamesLayout.currentVersion)
        #expect(layout.items == [
            .app(moduleID: "food-decision"),
            .app(moduleID: "sample-dice"),
        ])
    }

    @Test func codableRoundTripsExactly() throws {
        let collection = GamesLayout.Collection(
            id: UUID(), name: "Date night 🌙", members: ["a", "b"])
        let layout = GamesLayout(
            version: 1, items: [.collection(collection), .app(moduleID: "c")])
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(GamesLayout.self, from: data)
        #expect(decoded == layout)
    }

    @Test func itemIdentityDistinguishesAppsFromCollections() {
        let collectionID = UUID()
        let item = GamesLayout.Item.collection(
            .init(id: collectionID, name: "x", members: []))
        #expect(item.id == .collection(collectionID))
        #expect(GamesLayout.Item.app(moduleID: "a").id == .app("a"))
    }

    @Test func reconcileAppendsNewlyRegisteredModulesAtEnd() {
        let layout = GamesLayout(version: 1, items: [.app(moduleID: "a")])
        let result = layout.reconciled(with: ["a", "b", "c"])
        #expect(result.items == [
            .app(moduleID: "a"), .app(moduleID: "b"), .app(moduleID: "c"),
        ])
    }

    @Test func reconcileDropsStaleAppsEverywhere() {
        let collection = GamesLayout.Collection(id: UUID(), name: "n", members: ["gone", "b"])
        let layout = GamesLayout(version: 1,
                                 items: [.app(moduleID: "dead"), .collection(collection)])
        let result = layout.reconciled(with: ["b"])
        #expect(result.items.count == 1)
        guard case .collection(let kept) = result.items[0] else {
            Issue.record("expected the collection to survive"); return
        }
        #expect(kept.members == ["b"])
        #expect(kept.name == "n")           // rename survives reconcile
    }

    @Test func reconcileDissolvesEmptiedCollections() {
        let collection = GamesLayout.Collection(id: UUID(), name: "n", members: ["gone"])
        let layout = GamesLayout(version: 1, items: [.collection(collection)])
        let result = layout.reconciled(with: ["a"])
        #expect(result.items == [.app(moduleID: "a")])   // dissolved, then "a" appended
    }

    @Test func reconcileDropsDuplicateAppEntriesKeepingTheFirst() {
        let collection = GamesLayout.Collection(id: UUID(), name: "n", members: ["a"])
        let layout = GamesLayout(version: 1,
                                 items: [.app(moduleID: "a"), .collection(collection)])
        let result = layout.reconciled(with: ["a"])
        #expect(result.items == [.app(moduleID: "a")])   // member dup dropped → dissolved
    }

    @Test func reconcileLeavesAHealthyLayoutUntouched() {
        let collection = GamesLayout.Collection(id: UUID(), name: "n", members: ["b", "c"])
        let layout = GamesLayout(version: 1,
                                 items: [.collection(collection), .app(moduleID: "a")])
        #expect(layout.reconciled(with: ["a", "b", "c"]) == layout)
    }

    @Test func reconcileToleratesDuplicateRegisteredIDs() {
        let layout = GamesLayout(version: 1, items: [])
        let result = layout.reconciled(with: ["z", "z"])
        #expect(result.items == [.app(moduleID: "z")])
    }
}
