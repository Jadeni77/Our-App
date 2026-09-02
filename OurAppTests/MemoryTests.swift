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
    @Test func unreadableDataThrowsAndLeavesNothingBehind() throws {
        let directory = try tempDirectory()
        let store = MemoryPhotoStore(directory: directory)
        #expect(throws: MemoryPhotoStore.Failure.self) {
            _ = try store.save(Data("not an image".utf8))
        }
        // A throw that still wrote a file would orphan it — nothing references
        // it and there is no sweeper that would ever find it.
        let left = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        #expect(left.isEmpty)
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
        #expect(utc.component(.hour, from: try #require(stored.day)) == 12)
    }

    @Test func aMemoryCanHaveNoDayAtAll() throws {
        let context = try makeContext()
        context.insert(Memory(note: "somewhere, years ago", day: nil,
                              authorID: Partner.one.rawValue, photoIDs: ["a"]))
        try context.save()

        // Not a sentinel date: a guessed day would be wrong forever, and
        // `.distantPast` would sort as a real day.
        let stored = try context.fetch(FetchDescriptor<Memory>()).first
        #expect(stored?.day == nil)
        #expect(stored?.note == "somewhere, years ago")
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

@MainActor
struct MemoryThumbnailsTests {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func aMissingPhotoIsLookedForOnceAndThenRemembered() async throws {
        let directory = try tempDirectory()
        let cache = MemoryThumbnails(store: MemoryPhotoStore(directory: directory))

        await cache.loadIfNeeded("not-a-photo")
        #expect(cache.image(for: "not-a-photo") == nil)

        // The miss is cached, so a cell reappearing doesn't re-hit the disk.
        // Proven by planting the file afterwards: a second look must not find
        // it, because the first look already recorded that there was nothing.
        let store = MemoryPhotoStore(directory: directory)
        let planted = try store.save(Self.tinyJPEG())
        try FileManager.default.moveItem(at: store.thumbnailURL(planted),
                                         to: store.thumbnailURL("not-a-photo"))

        await cache.loadIfNeeded("not-a-photo")
        #expect(cache.image(for: "not-a-photo") == nil)
    }

    /// **The hero's whole bug, pinned.** Reading the grid's 400px tier for a
    /// surface several times a grid tile's size is invisible against a flat
    /// debug colour, which is exactly how it shipped once already — so this
    /// proves the *size* the full tier decodes at, not merely that it returns
    /// something. A source large enough that the two tiers must clamp to
    /// different targets is the only way that distinction is observable at
    /// all.
    @MainActor
    @Test func theFullTierDecodesAtFullSizeNotGridSize() async throws {
        let directory = try tempDirectory()
        let store = MemoryPhotoStore(directory: directory)
        let id = try store.save(Self.sourceJPEG())
        let cache = MemoryThumbnails(store: store)

        await cache.loadFullIfNeeded(id)

        let full = try #require(cache.fullImage(for: id))
        #expect(max(full.size.width, full.size.height) > CGFloat(MemoryPhotoStore.thumbnailMaxPixel))
        #expect(max(full.size.width, full.size.height) <= CGFloat(MemoryPhotoStore.fullMaxPixel))
    }

    /// **The tension `forget`'s own doc comment names, now doubled.** A cover
    /// that was a miss when the hero was last open has to stop being a miss
    /// in *both* tiers once sync lands the file, or the hero — unlike the
    /// grid it shares this cache with — would still show `Color.clear` until
    /// the app relaunched.
    @Test func forgettingAMissClearsBothTiers() async throws {
        let directory = try tempDirectory()
        let cache = MemoryThumbnails(store: MemoryPhotoStore(directory: directory))

        await cache.loadIfNeeded("missing")
        await cache.loadFullIfNeeded("missing")
        #expect(cache.image(for: "missing") == nil)
        #expect(cache.fullImage(for: "missing") == nil)

        let store = MemoryPhotoStore(directory: directory)
        let planted = try store.save(Self.tinyJPEG())
        try FileManager.default.moveItem(at: store.url(planted), to: store.url("missing"))
        try FileManager.default.moveItem(at: store.thumbnailURL(planted),
                                         to: store.thumbnailURL("missing"))

        cache.forget("missing")
        await cache.loadIfNeeded("missing")
        await cache.loadFullIfNeeded("missing")

        #expect(cache.image(for: "missing") != nil)
        #expect(cache.fullImage(for: "missing") != nil)
    }

    /// A deliberately large source, so the full tier's clamp to
    /// `MemoryPhotoStore.fullMaxPixel` and the grid tier's clamp to
    /// `thumbnailMaxPixel` land on two different sizes rather than both
    /// trivially matching the source.
    @MainActor
    private static func sourceJPEG(width: Int = 3000, height: Int = 2000) -> Data {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.jpegData(compressionQuality: 1.0)!
    }

    private static func tinyJPEG() -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let size = CGSize(width: 40, height: 40)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }.jpegData(compressionQuality: 0.9)!
    }
}

@MainActor
struct MemoryTimelineTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try Persistence.makeContainer(inMemory: true))
    }

    private func memory(_ note: String, day: Date?, updated: Date) -> Memory {
        let memory = Memory(note: note, day: day,
                            authorID: Partner.one.rawValue, photoIDs: ["a"])
        memory.updatedAt = updated
        return memory
    }

    private func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: 800_000_000 + offset)
    }

    @Test func datedMemoriesComeBackNewestFirst() {
        let split = MemoryTimeline.ordered([
            memory("older", day: date(0), updated: date(0)),
            memory("newest", day: date(200_000), updated: date(0)),
            memory("middle", day: date(100_000), updated: date(0)),
        ])
        #expect(split.dated.map(\.note) == ["newest", "middle", "older"])
        #expect(split.undated.isEmpty)
    }

    @Test func memoriesFromTheSameDayFallBackToWhenTheyWereAdded() {
        // `day` is anchored to noon UTC, so a whole trip's worth of memories
        // tie exactly. Without this tiebreak their order is whatever the store
        // returned, which can differ between launches.
        let sameDay = date(0)
        let split = MemoryTimeline.ordered([
            memory("added first", day: sameDay, updated: date(10)),
            memory("added last", day: sameDay, updated: date(30)),
            memory("added second", day: sameDay, updated: date(20)),
        ])
        #expect(split.dated.map(\.note) == ["added last", "added second", "added first"])
    }

    @Test func undatedMemoriesAreSeparatedOutAndGoLast() {
        let split = MemoryTimeline.ordered([
            memory("no idea when", day: nil, updated: date(10)),
            memory("dated", day: date(0), updated: date(0)),
            memory("also no idea", day: nil, updated: date(50)),
        ])
        // Split rather than interleaved: the grid draws them under their own
        // heading, and a `SortDescriptor` cannot express this.
        #expect(split.dated.map(\.note) == ["dated"])
        #expect(split.undated.map(\.note) == ["also no idea", "no idea when"])
    }

    @Test func anEmptyTimelineIsEmptyOnBothSides() {
        let split = MemoryTimeline.ordered([])
        #expect(split.dated.isEmpty)
        #expect(split.undated.isEmpty)
    }
}
