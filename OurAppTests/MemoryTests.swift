import Foundation
import SwiftData
import Testing
import UIKit
@testable import OurApp

struct MemoryPhotoStoreTests {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A deliberately large, deliberately non-square source, so "long edge" is
    /// unambiguous and downscaling has something real to do.
    @MainActor
    private func sourceJPEG(width: Int = 3000, height: Int = 2000) -> Data {
        let size = CGSize(width: width, height: height)
        // scale 1 so points == pixels. The default is the screen's scale, which
        // silently makes a "800×600" source 2400×1800 and invalidates any
        // assertion about the source's real dimensions.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        }
        return image.jpegData(compressionQuality: 1.0)!
    }

    @MainActor
    @Test func savingWritesADownscaledCopyAndAThumbnail() throws {
        let store = MemoryPhotoStore(directory: try tempDirectory())
        let original = sourceJPEG()

        let id = try store.save(original)

        let full = store.image(for: id)
        let thumb = store.thumbnail(for: id)
        #expect(full != nil)
        #expect(thumb != nil)
        #expect(max(full!.size.width, full!.size.height) <= CGFloat(MemoryPhotoStore.fullMaxPixel))
        #expect(max(thumb!.size.width, thumb!.size.height) <= CGFloat(MemoryPhotoStore.thumbnailMaxPixel))
        // The point of downscaling: the stored copy is materially smaller.
        let storedBytes = try Data(contentsOf: store.url(id)).count
        #expect(storedBytes < original.count / 2)
    }

    @MainActor
    @Test func aspectRatioSurvivesDownscaling() throws {
        let store = MemoryPhotoStore(directory: try tempDirectory())
        let id = try store.save(sourceJPEG(width: 3000, height: 2000))
        let full = store.image(for: id)!
        // 3:2 in, 3:2 out — a squashed photo is worse than a large one.
        #expect(abs(full.size.width / full.size.height - 1.5) < 0.02)
    }

    @MainActor
    @Test func aSmallerImageIsNotUpscaled() throws {
        let store = MemoryPhotoStore(directory: try tempDirectory())
        let id = try store.save(sourceJPEG(width: 800, height: 600))
        let full = store.image(for: id)!
        #expect(max(full.size.width, full.size.height) <= 800)
    }

    @MainActor
    @Test func deletingRemovesBothFiles() throws {
        let store = MemoryPhotoStore(directory: try tempDirectory())
        let id = try store.save(sourceJPEG())
        #expect(FileManager.default.fileExists(atPath: store.url(id).path))

        store.delete(id)

        #expect(!FileManager.default.fileExists(atPath: store.url(id).path))
        #expect(!FileManager.default.fileExists(atPath: store.thumbnailURL(id).path))
    }

    @MainActor
    @Test func aMissingFileReadsAsNilRatherThanThrowing() throws {
        let store = MemoryPhotoStore(directory: try tempDirectory())
        // Principle 7: a lost file is a placeholder, never a crash.
        #expect(store.image(for: "not-a-photo") == nil)
        #expect(store.thumbnail(for: "not-a-photo") == nil)
    }

    @MainActor
    @Test func unreadableDataThrowsRatherThanWritingRubbish() throws {
        let store = MemoryPhotoStore(directory: try tempDirectory())
        #expect(throws: MemoryPhotoStore.Failure.self) {
            _ = try store.save(Data("not an image".utf8))
        }
    }
}

@MainActor
struct MemoryRecordTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try Persistence.makeContainer(inMemory: true))
    }

    @Test func aMemoryRoundTripsWithItsPhotoOrder() throws {
        let context = try makeContext()
        let day = Date(timeIntervalSinceReferenceDate: 800_000_000)
        context.insert(Memory(note: "Kyoto, first morning",
                              day: day,
                              authorID: Partner.one.rawValue,
                              photoIDs: ["a", "b", "c"]))
        try context.save()

        let stored = try context.fetch(FetchDescriptor<Memory>()).first
        #expect(stored?.note == "Kyoto, first morning")
        // Order is meaningful — the first photo is what the grid shows.
        #expect(stored?.photoIDs == ["a", "b", "c"])
        #expect(stored?.deletedAt == nil)
    }

    @Test func theDayIsStoredAsAFloatingCivilDay() throws {
        let context = try makeContext()
        context.insert(Memory(note: "", day: Date(timeIntervalSinceReferenceDate: 800_000_000),
                              authorID: Partner.one.rawValue, photoIDs: ["a"]))
        try context.save()

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let stored = try context.fetch(FetchDescriptor<Memory>()).first!
        #expect(utc.component(.hour, from: stored.day) == 12)
    }

    @Test func theVisiblePredicateHidesTombstones() throws {
        let context = try makeContext()
        let kept = Memory(note: "kept", day: .now,
                          authorID: Partner.one.rawValue, photoIDs: ["a"])
        let gone = Memory(note: "gone", day: .now,
                          authorID: Partner.one.rawValue, photoIDs: ["b"])
        context.insert(kept)
        context.insert(gone)
        gone.deletedAt = .now
        try context.save()

        let visible = try context.fetch(FetchDescriptor<Memory>(predicate: Memory.visible))
        #expect(visible.map(\.note) == ["kept"])
    }

    @Test func aMemoryKeepsAtMostNinePhotos() throws {
        let context = try makeContext()
        let tooMany = (1...15).map(String.init)
        context.insert(Memory(note: "", day: .now,
                              authorID: Partner.one.rawValue, photoIDs: tooMany))
        try context.save()

        // The picker caps selection, but the record is the last line of defence.
        #expect(try context.fetch(FetchDescriptor<Memory>()).first?.photoIDs.count
                == Memory.maxPhotos)
    }
}
