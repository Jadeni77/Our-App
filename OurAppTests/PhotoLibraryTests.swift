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

        PhotoLibrary.seed(in: store, authorID: "me")
        #expect(PhotoLibrary.all(in: store).map(\.assetID).sorted() == ["a", "b"])
    }

    /// Run on every launch, so a second pass must cost nothing and change
    /// nothing.
    @Test func seedingTwiceDoesNotDoubleTheLibrary() throws {
        let store = try context()
        store.insert(Memory(note: "Kyoto", day: .now, authorID: "me", photoIDs: ["a"]))
        try store.save()

        PhotoLibrary.seed(in: store, authorID: "me")
        PhotoLibrary.seed(in: store, authorID: "me")
        #expect(PhotoLibrary.all(in: store).count == 1)
    }

    /// A picture the other phone added arrives with its own record; seeding
    /// must not claim it.
    @Test func seedingDoesNotStealAuthorship() throws {
        let store = try context()
        store.insert(Photo(assetID: "a", authorID: "them"))
        store.insert(Memory(note: "theirs", day: .now, authorID: "them", photoIDs: ["a"]))
        try store.save()

        PhotoLibrary.seed(in: store, authorID: "me")
        #expect(PhotoLibrary.all(in: store).first?.authorID == "them")
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
