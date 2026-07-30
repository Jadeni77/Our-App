import Foundation
import SwiftUI
import Testing
@testable import OurApp

@MainActor
struct GamesLayoutStoreTests {
    private func descriptor(_ id: String) -> ModuleDescriptor {
        ModuleDescriptor(id: id, name: "Test", emoji: "🧪",
                         makeEntryView: { AnyView(EmptyView()) })
    }

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("games-layout-\(UUID().uuidString).json")
    }

    @Test func freshStoreBuildsDefaultLayoutAndSavesIt() throws {
        let url = tempFile()
        let store = GamesLayoutStore(modules: [descriptor("a"), descriptor("b")],
                                     fileURL: url)
        #expect(store.layout.items == [.app(moduleID: "a"), .app(moduleID: "b")])
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func storeReloadsWhatWasSavedAndReconciles() throws {
        let url = tempFile()
        let saved = GamesLayout(
            version: 1,
            items: [.app(moduleID: "b"), .app(moduleID: "stale")])
        try JSONEncoder().encode(saved).write(to: url)

        let store = GamesLayoutStore(modules: [descriptor("a"), descriptor("b")],
                                     fileURL: url)
        // "stale" dropped, missing "a" appended, saved order kept for "b".
        #expect(store.layout.items == [.app(moduleID: "b"), .app(moduleID: "a")])
    }

    @Test func corruptFileFallsBackToDefault() throws {
        let url = tempFile()
        try Data("not json 🙃".utf8).write(to: url)
        let store = GamesLayoutStore(modules: [descriptor("a")], fileURL: url)
        #expect(store.layout.items == [.app(moduleID: "a")])
    }

    @Test func newerVersionOnDiskFallsBackToDefault() throws {
        let url = tempFile()
        let future = GamesLayout(version: 99, items: [.app(moduleID: "b")])
        try JSONEncoder().encode(future).write(to: url)
        let store = GamesLayoutStore(modules: [descriptor("a")], fileURL: url)
        #expect(store.layout.items == [.app(moduleID: "a")])
        #expect(store.layout.version == GamesLayout.currentVersion)
    }

    @Test func moduleLookupResolvesDescriptors() {
        let store = GamesLayoutStore(modules: [descriptor("a")], fileURL: tempFile())
        #expect(store.module(for: "a")?.emoji == "🧪")
        #expect(store.module(for: "nope") == nil)
    }

    @Test func moveItemReordersWithRemoveThenInsertSemantics() {
        let store = GamesLayoutStore(
            modules: [descriptor("a"), descriptor("b"), descriptor("c")],
            fileURL: tempFile())
        store.moveItem(id: .app("a"), toIndex: 1)
        #expect(store.layout.items.map(\.id) == [.app("b"), .app("a"), .app("c")])
    }

    @Test func formCollectionTakesTargetSlotAndPersists() throws {
        let url = tempFile()
        let store = GamesLayoutStore(
            modules: [descriptor("a"), descriptor("b"), descriptor("c")], fileURL: url)
        let id = store.formCollection(target: "b", dragged: "a", named: "New collection")
        #expect(id != nil)
        guard case .collection(let made) = store.layout.items[0] else {
            Issue.record("collection should sit in b's original slot"); return
        }
        #expect(made.members == ["b", "a"])
        #expect(made.name == "New collection")
        #expect(store.layout.items.map(\.id) == [.collection(made.id), .app("c")])

        // Mutations persist immediately: a second store sees the same layout.
        let reloaded = GamesLayoutStore(
            modules: [descriptor("a"), descriptor("b"), descriptor("c")], fileURL: url)
        #expect(reloaded.layout == store.layout)
    }

    @Test func formCollectionRefusesNonRootParticipants() {
        let store = GamesLayoutStore(
            modules: [descriptor("a"), descriptor("b")], fileURL: tempFile())
        _ = store.formCollection(target: "b", dragged: "a", named: "n")
        // "a" is now inside a collection — it can't form another one.
        #expect(store.formCollection(target: "a", dragged: "b", named: "n") == nil)
    }

    @Test func addToCollectionAppendsAndRemovesFromRoot() throws {
        let store = GamesLayoutStore(
            modules: [descriptor("a"), descriptor("b"), descriptor("c")], fileURL: tempFile())
        let id = try #require(store.formCollection(target: "a", dragged: "b", named: "n"))
        store.addToCollection(id, moduleID: "c")
        guard case .collection(let made) = store.layout.items[0] else {
            Issue.record("expected collection"); return
        }
        #expect(made.members == ["a", "b", "c"])
        #expect(store.layout.items.count == 1)
    }

    @Test func moveMemberReordersInsideCollection() throws {
        let store = GamesLayoutStore(
            modules: [descriptor("a"), descriptor("b"), descriptor("c")], fileURL: tempFile())
        let id = try #require(store.formCollection(target: "a", dragged: "b", named: "n"))
        store.addToCollection(id, moduleID: "c")
        store.moveMember(in: id, moduleID: "c", toIndex: 0)
        guard case .collection(let made) = store.layout.items[0] else {
            Issue.record("expected collection at items[0]"); return
        }
        #expect(made.members == ["c", "a", "b"])
    }

    @Test func moveMemberToRootAppendsAndDissolvesEmptyCollection() throws {
        let store = GamesLayoutStore(
            modules: [descriptor("a"), descriptor("b"), descriptor("c")], fileURL: tempFile())
        let id = try #require(store.formCollection(target: "a", dragged: "b", named: "n"))
        store.moveMemberToRoot("b", from: id)
        #expect(store.layout.items.map(\.id) == [.collection(id), .app("c"), .app("b")])
        store.moveMemberToRoot("a", from: id)
        // Last member left → collection dissolves (S5).
        #expect(store.layout.items.map(\.id) == [.app("c"), .app("b"), .app("a")])
    }

    @Test func renameCollectionStoresNameVerbatim() throws {
        let store = GamesLayoutStore(
            modules: [descriptor("a"), descriptor("b")], fileURL: tempFile())
        let id = try #require(store.formCollection(target: "a", dragged: "b", named: "n"))
        store.renameCollection(id, to: "  周末去哪儿 🎡 ")
        guard case .collection(let made) = store.layout.items[0] else {
            Issue.record("expected collection at items[0]"); return
        }
        #expect(made.name == "  周末去哪儿 🎡 ")   // verbatim — user data (S6)
    }
}
