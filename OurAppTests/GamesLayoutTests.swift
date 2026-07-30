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

    // MARK: - v2: external app tiles (S7)

    private func external(named name: String = "Identity V",
                          id: UUID = UUID()) -> GamesLayout.ExternalApp {
        GamesLayout.ExternalApp(id: id, name: name, emoji: "🎮",
                                artworkURL: nil,
                                launchURL: URL(string: "identityv://"),
                                storeURL: nil)
    }

    @Test func versionOneDocumentsDecodeLosslessly() throws {
        // Captured v1 wire format (synthesized Codable): no `externalApps` key.
        let v1JSON = """
        {"version":1,"items":[\
        {"app":{"moduleID":"food-decision"}},\
        {"collection":{"_0":{"id":"11111111-1111-1111-1111-111111111111",\
        "name":"Ours 💗","members":["a","b"]}}}]}
        """
        let decoded = try JSONDecoder().decode(GamesLayout.self,
                                               from: Data(v1JSON.utf8))
        #expect(decoded.version == 1)
        #expect(decoded.items.count == 2)
        #expect(decoded.items[0] == .app(moduleID: "food-decision"))
        guard case .collection(let collection) = decoded.items[1] else {
            Issue.record("expected the v1 collection to survive decoding"); return
        }
        #expect(collection.members == ["a", "b"])
        #expect(decoded.externalApps.isEmpty)
        #expect(decoded.learnedSchemes.isEmpty)
    }

    @Test func learnedSchemesRoundTripAndSurviveReconcile() throws {
        let learned = GamesLayout.LearnedScheme(name: "Wild Rift",
                                                scheme: "wildrift://")
        let layout = GamesLayout(version: GamesLayout.currentVersion,
                                 items: [.app(moduleID: "a")],
                                 learnedSchemes: [learned])
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(GamesLayout.self, from: data)
        #expect(decoded.learnedSchemes == [learned])
        // Knowledge is never dropped by reconcile — it isn't a tile.
        #expect(layout.reconciled(with: ["a"]).learnedSchemes == [learned])
    }

    @Test func codableRoundTripsExternalsExactly() throws {
        let identity = external()
        let collection = GamesLayout.Collection(
            id: UUID(), name: "Games 🎮", members: ["a", identity.memberKey])
        let layout = GamesLayout(
            version: GamesLayout.currentVersion,
            items: [.collection(collection), .external(externalID: identity.id)],
            externalApps: [identity])
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(GamesLayout.self, from: data)
        #expect(decoded == layout)
    }

    @Test func externalItemIdentity() {
        let id = UUID()
        #expect(GamesLayout.Item.external(externalID: id).id == .external(id))
    }

    @Test func reconcileNeverDropsExternalTilesOrMembers() {
        let identity = external()
        let lonely = external(named: "Genshin")
        let collection = GamesLayout.Collection(
            id: UUID(), name: "n", members: [lonely.memberKey, "stale"])
        let layout = GamesLayout(
            version: 2,
            items: [.external(externalID: identity.id), .collection(collection)],
            externalApps: [identity, lonely])
        let result = layout.reconciled(with: ["a"])
        // External root tile kept; the collection survives on its external
        // member alone; the stale module member drops; "a" appends.
        #expect(result.items.count == 3)
        #expect(result.items[0] == .external(externalID: identity.id))
        guard case .collection(let kept) = result.items[1] else {
            Issue.record("expected the collection to survive on its external member"); return
        }
        #expect(kept.members == [lonely.memberKey])
        #expect(result.items[2] == .app(moduleID: "a"))
        #expect(result.externalApps == [identity, lonely])
    }

    @Test func reconcileDropsDanglingExternalReferences() {
        let danglingID = UUID()
        let collection = GamesLayout.Collection(
            id: UUID(), name: "n", members: [UUID().uuidString, "a"])
        let layout = GamesLayout(
            version: 2,
            items: [.external(externalID: danglingID), .collection(collection)],
            externalApps: [])
        let result = layout.reconciled(with: ["a"])
        // No registry entry backs either reference — both drop; the module
        // member keeps the collection alive.
        guard case .collection(let kept) = result.items[0] else {
            Issue.record("expected the collection to survive on its module member"); return
        }
        #expect(kept.members == ["a"])
        #expect(result.items.count == 1)
    }

    @Test func reconcileRematerializesUnreferencedRegistryEntries() {
        let identity = external()
        let layout = GamesLayout(version: 2,
                                 items: [.app(moduleID: "a")],
                                 externalApps: [identity])
        let result = layout.reconciled(with: ["a"])
        // The registry is the source of truth for externals (S7: user data is
        // never auto-dropped) — an entry that lost its tile gets it back.
        #expect(result.items == [
            .app(moduleID: "a"), .external(externalID: identity.id),
        ])
    }
}
