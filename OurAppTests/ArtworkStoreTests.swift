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

    private func pngData() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }

    @Test func storedArtworkRoundTripsAcrossInstances() throws {
        let directory = tempDirectory()
        let id = UUID()
        let store = ArtworkStore(directory: directory)
        store.storeArtwork(pngData(), for: id)
        #expect(store.image(for: id) != nil)

        let second = ArtworkStore(directory: directory)   // fresh memory cache
        #expect(second.image(for: id) != nil)             // served from disk
    }

    @Test func missingArtworkIsNil() {
        let store = ArtworkStore(directory: tempDirectory())
        #expect(store.image(for: UUID()) == nil)
    }

    @Test func garbageOnDiskFailsSoftToNil() throws {
        let directory = tempDirectory()
        let id = UUID()
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        try Data("nope".utf8).write(to: directory.appendingPathComponent("\(id.uuidString).png"))
        let store = ArtworkStore(directory: directory)
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
}
