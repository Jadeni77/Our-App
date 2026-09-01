import Foundation
import SwiftData
import Testing
@testable import OurApp

@MainActor
struct PhotoLibraryTests {
    private func context() throws -> ModelContext {
        ModelContext(try Persistence.makeContainer(inMemory: true))
    }

    /// Photos taken before albums existed must appear in the library, or the
    /// feature launches empty on the only phone whose pictures matter.
    @Test func everyAssetInAMemoryGetsARecord() throws {
        let store = try context()
        store.insert(Memory(note: "Kyoto", day: .now, authorID: "me",
                            photoIDs: ["a", "b"]))
        try store.save()

        PhotoLibrary.seed(in: store)
        #expect(PhotoLibrary.all(in: store).map(\.assetID).sorted() == ["a", "b"])
    }

    /// Run on every launch, so a second pass must cost nothing and change
    /// nothing.
    @Test func seedingTwiceDoesNotDoubleTheLibrary() throws {
        let store = try context()
        store.insert(Memory(note: "Kyoto", day: .now, authorID: "me", photoIDs: ["a"]))
        try store.save()

        PhotoLibrary.seed(in: store)
        PhotoLibrary.seed(in: store)
        #expect(PhotoLibrary.all(in: store).count == 1)
    }

    /// A picture the other phone added arrives with its own record; seeding
    /// must not overwrite its author.
    @Test func existingRecordsRetainAuthorship() throws {
        let store = try context()
        store.insert(Photo(assetID: "a", authorID: "them"))
        store.insert(Memory(note: "theirs", day: .now, authorID: "them", photoIDs: ["a"]))
        try store.save()

        PhotoLibrary.seed(in: store)
        #expect(PhotoLibrary.all(in: store).first?.authorID == "them")
    }

    /// When an asset has no Photo yet, seeding credits it to the memory's
    /// author, not whoever is holding the phone.
    @Test func seedingCreditsToMemoryAuthor() throws {
        let store = try context()
        store.insert(Memory(note: "theirs", day: .now, authorID: "them", photoIDs: ["new"]))
        try store.save()

        PhotoLibrary.seed(in: store)
        #expect(PhotoLibrary.all(in: store).first?.authorID == "them")
    }

    /// A deliberately deleted photo must not be resurrected. The existing fetch
    /// is unfiltered so tombstoned photos are known, preventing re-creation.
    @Test func seedingDoesNotResurrectTombstonedPhotos() throws {
        let store = try context()
        let deleted = Photo(assetID: "deleted", authorID: "me")
        deleted.deletedAt = .now
        store.insert(deleted)
        store.insert(Memory(note: "had it once", day: .now, authorID: "me", photoIDs: ["deleted"]))
        try store.save()

        PhotoLibrary.seed(in: store)
        // Should have only the deleted one, and it should still be deleted
        #expect(PhotoLibrary.all(in: store).isEmpty)
        let all = try? store.fetch(FetchDescriptor<Photo>())
        #expect(all?.first?.deletedAt != nil)
    }

    /// **The order has to be the same on both phones.**
    ///
    /// Seeding used to leave `takenAt` nil, so `sortDate` fell back to
    /// `addedAt` — when *this* phone happened to run the seed. Two phones that
    /// seeded in different orders, or on different days, sorted the same
    /// pictures differently and neither order meant anything. The memory's day
    /// is a floating civil day both already agree on (H8).
    @Test func seedingTakesTheDateFromTheMemory() throws {
        let store = try context()
        let day = Date(timeIntervalSinceReferenceDate: 700_000)
        store.insert(Memory(note: "Kyoto", day: day, authorID: "me", photoIDs: ["a"]))
        try store.save()

        PhotoLibrary.seed(in: store)
        let photo = try #require(PhotoLibrary.all(in: store).first)
        #expect(photo.takenAt == SpecialDateSchedule.anchor(for: day))
        #expect(photo.sortDate == photo.takenAt)
    }

    /// A row seeded before the date rule existed gets one on the next pass —
    /// otherwise the fix only helps pictures nobody had yet, and the phones
    /// this branch has already run on keep sorting by when they seeded.
    @Test func seedingBackfillsADateOntoAnExistingRow() throws {
        let store = try context()
        store.insert(Photo(assetID: "a", authorID: "them"))
        let day = Date(timeIntervalSinceReferenceDate: 700_000)
        store.insert(Memory(note: "Kyoto", day: day, authorID: "them", photoIDs: ["a"]))
        try store.save()

        PhotoLibrary.seed(in: store)
        let photo = try #require(PhotoLibrary.all(in: store).first)
        #expect(photo.takenAt == SpecialDateSchedule.anchor(for: day))
        // Backfill, not re-creation: the row it already had, author and all.
        #expect(photo.authorID == "them")
        #expect(PhotoLibrary.all(in: store).count == 1)
    }

    /// **The same answer on both phones, whatever order their fetches come
    /// back in.** A picture can sit in two memories; taking whichever the fetch
    /// returned first would hand the two libraries different dates for it,
    /// which is the divergence the date exists to remove. Earliest wins.
    @Test func aPhotoInTwoMemoriesTakesTheEarlierDay() throws {
        let store = try context()
        let earlier = Date(timeIntervalSinceReferenceDate: 100_000)
        let later = Date(timeIntervalSinceReferenceDate: 900_000)
        store.insert(Memory(note: "later", day: later, authorID: "me", photoIDs: ["a"]))
        store.insert(Memory(note: "earlier", day: earlier, authorID: "me", photoIDs: ["a"]))
        try store.save()

        PhotoLibrary.seed(in: store)
        #expect(PhotoLibrary.all(in: store).first?.takenAt
                == SpecialDateSchedule.anchor(for: earlier))
    }

    /// An undated memory stays undated. A guessed date would be wrong forever,
    /// which is worse than none (H23).
    @Test func seedingLeavesAnUndatedMemorysPhotosUndated() throws {
        let store = try context()
        store.insert(Memory(note: "shoebox", day: nil, authorID: "me", photoIDs: ["a"]))
        try store.save()

        PhotoLibrary.seed(in: store)
        #expect(PhotoLibrary.all(in: store).first?.takenAt == nil)
    }

    /// Newest first, falling back to when it arrived for anything with no
    /// capture date — which is everything that predates this record.
    @Test func theLibraryIsNewestFirst() throws {
        let store = try context()
        let older = Photo(assetID: "old", authorID: "me")
        older.takenAt = Date(timeIntervalSinceReferenceDate: 1000)
        let newer = Photo(assetID: "new", authorID: "me")
        newer.takenAt = Date(timeIntervalSinceReferenceDate: 2000)
        store.insert(older); store.insert(newer)
        try store.save()

        #expect(PhotoLibrary.all(in: store).map(\.assetID) == ["new", "old"])
    }
}

/// Deleting a memory is the one delete in this app that destroys bytes, so it
/// is the one delete that has to retire library rows as well.
@MainActor
struct PhotoRetirementTests {
    private func context() throws -> ModelContext {
        ModelContext(try Persistence.makeContainer(inMemory: true))
    }

    /// Before this, deleting a memory with six photos left six tiles in All
    /// photos forever: placeholders that could never load, with no photo-delete
    /// anywhere to clear them.
    @Test func deletingAMemoryRetiresItsPhotos() throws {
        let store = try context()
        let memory = Memory(note: "Kyoto", day: .now, authorID: "me", photoIDs: ["a", "b"])
        store.insert(memory)
        try store.save()
        PhotoLibrary.seed(in: store)
        #expect(PhotoLibrary.all(in: store).count == 2)

        // What `MemoryDetailView.delete()` does: tombstone first, then retire.
        memory.deletedAt = .now
        try store.save()
        PhotoLibrary.retire(assets: memory.photoIDs, in: store)

        #expect(PhotoLibrary.all(in: store).isEmpty)
    }

    /// **Only what the delete actually orphaned.** A picture in two memories
    /// still has one of them, and its files with it.
    @Test func aPhotoAnotherMemoryStillNamesSurvives() throws {
        let store = try context()
        let deleted = Memory(note: "one", day: .now, authorID: "me", photoIDs: ["shared", "solo"])
        store.insert(deleted)
        store.insert(Memory(note: "two", day: .now, authorID: "me", photoIDs: ["shared"]))
        try store.save()
        PhotoLibrary.seed(in: store)

        deleted.deletedAt = .now
        try store.save()
        PhotoLibrary.retire(assets: deleted.photoIDs, in: store)

        #expect(PhotoLibrary.all(in: store).map(\.assetID) == ["shared"])
    }

    /// The guard that keeps this from becoming reconciliation. Called while the
    /// memory is still visible — the wrong order — it retires nothing, which is
    /// the harmless direction.
    @Test func retiringBeforeTheTombstoneIsDurableDoesNothing() throws {
        let store = try context()
        let memory = Memory(note: "Kyoto", day: .now, authorID: "me", photoIDs: ["a"])
        store.insert(memory)
        try store.save()
        PhotoLibrary.seed(in: store)

        PhotoLibrary.retire(assets: memory.photoIDs, in: store)

        #expect(PhotoLibrary.all(in: store).count == 1)
    }

    /// **A `Photo` that arrives before its `Memory` must not be retired.**
    ///
    /// The two are independent records, so this window is normal rather than
    /// exotic, and a sticky tombstone written in it deletes the picture from
    /// both phones forever. `retire` is scoped to the assets a delete just
    /// orphaned precisely so it can never see this row.
    @Test func aPhotoWhoseMemoryHasNotArrivedIsLeftAlone() throws {
        let store = try context()
        store.insert(Photo(assetID: "early", authorID: "them"))
        let memory = Memory(note: "mine", day: .now, authorID: "me", photoIDs: ["a"])
        store.insert(memory)
        try store.save()
        PhotoLibrary.seed(in: store)

        memory.deletedAt = .now
        try store.save()
        PhotoLibrary.retire(assets: memory.photoIDs, in: store)

        #expect(PhotoLibrary.all(in: store).map(\.assetID) == ["early"])
    }
}
