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
}
