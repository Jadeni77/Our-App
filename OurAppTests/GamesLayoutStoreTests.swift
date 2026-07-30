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
}
