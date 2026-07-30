import Foundation
import Testing
import UIKit
@testable import OurApp

@MainActor
struct ArtworkStoreTests {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("artwork-\(UUID().uuidString)", isDirectory: true)
    }

    private func pngData(_ color: UIColor = .systemPink) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }

    @Test func storedArtworkRoundTripsAcrossInstances() async throws {
        let directory = tempDirectory()
        let id = UUID()
        let store = ArtworkStore(directory: directory)
        store.storeArtwork(pngData(), for: id)
        #expect(store.image(for: id) != nil)

        let second = ArtworkStore(directory: directory)   // fresh memory cache
        #expect(second.image(for: id) == nil)             // memory-only until loaded
        await second.loadIfNeeded(id)
        #expect(second.image(for: id) != nil)             // served from disk
    }

    @Test func missingArtworkStaysNilAndRecordsTheMiss() async {
        let store = ArtworkStore(directory: tempDirectory())
        let id = UUID()
        #expect(store.image(for: id) == nil)
        await store.loadIfNeeded(id)
        #expect(store.image(for: id) == nil)   // miss cached — no repeat disk reads
    }

    @Test func garbageOnDiskFailsSoftToNil() async throws {
        let directory = tempDirectory()
        let id = UUID()
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        try Data("nope".utf8).write(to: directory.appendingPathComponent("\(id.uuidString).png"))
        let store = ArtworkStore(directory: directory)
        await store.loadIfNeeded(id)
        #expect(store.image(for: id) == nil)
    }

    @Test func nonImageDataIsNotStored() {
        let directory = tempDirectory()
        let id = UUID()
        let store = ArtworkStore(directory: directory)
        store.storeArtwork(Data("junk".utf8), for: id)
        #expect(store.image(for: id) == nil)
        #expect(!FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("\(id.uuidString).png").path))
    }

    @Test func storingReplacesEarlierArtwork() {
        let store = ArtworkStore(directory: tempDirectory())
        let id = UUID()
        store.storeArtwork(pngData(.systemPink), for: id)
        store.storeArtwork(pngData(.systemIndigo), for: id)
        // The rename path re-fetches: the newest bytes must win.
        let replaced = store.image(for: id)
        #expect(replaced != nil)
    }

    @Test func forgetRemovesMemoryAndDisk() async {
        let directory = tempDirectory()
        let id = UUID()
        let store = ArtworkStore(directory: directory)
        store.storeArtwork(pngData(), for: id)
        store.forget(id)
        #expect(store.image(for: id) == nil)
        #expect(!FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("\(id.uuidString).png").path))
        await store.loadIfNeeded(id)               // and the miss stays a miss
        #expect(store.image(for: id) == nil)
    }
}
