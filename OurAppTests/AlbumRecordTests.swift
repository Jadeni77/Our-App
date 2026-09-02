import Foundation
import SwiftData
import Testing
@testable import OurApp

@MainActor
struct AlbumRecordTests {
    private func context() throws -> ModelContext {
        ModelContext(try Persistence.makeContainer(inMemory: true))
    }

    /// Both phones filing one picture into one album must write one row.
    @Test func aMembershipIDIsItsAlbumAndItsPhoto() {
        let album = UUID()
        #expect(AlbumEntry.id(album: album, asset: "abc")
                == AlbumEntry.id(album: album, asset: "abc"))
        #expect(AlbumEntry.id(album: album, asset: "abc")
                != AlbumEntry.id(album: album, asset: "xyz"))
        #expect(AlbumEntry.id(album: album, asset: "abc")
                != AlbumEntry.id(album: UUID(), asset: "abc"))
    }

    /// One row per picture, however many phones notice it.
    @Test func aPhotoIDIsItsAsset() {
        #expect(Photo.id(for: "asset-1") == Photo.id(for: "asset-1"))
        #expect(Photo.id(for: "asset-1") != Photo.id(for: "asset-2"))
    }

    /// Not a CloudKit-legality check — `Persistence.makeContainer(inMemory:
    /// true)` sets `cloudKitDatabase: .none`, so mirroring's optional-or-default
    /// rule is never enforced here; `CloudKitSchemaTests` is what actually
    /// proves that. What this does prove: the three types insert and save with
    /// nothing but their required init arguments, and come back with the
    /// tombstone/optional shape §7 expects — deletedAt unset, an unset cover
    /// falling back to nil rather than some sentinel, and a membership's
    /// foreign key intact.
    @Test func theRecordsSatisfyTheCloudKitRules() throws {
        let store = try context()
        let photo = Photo(assetID: "a", authorID: "me")
        let album = Album(name: "🎀", authorID: "me")
        let entry = AlbumEntry(albumID: album.id, assetID: "a", authorID: "me")
        store.insert(photo); store.insert(album); store.insert(entry)
        try store.save()

        #expect(photo.deletedAt == nil)
        #expect(album.coverAssetID == nil)
        #expect(entry.albumID == album.id)
    }

    /// The couple's line about the album travels like any other field —
    /// through an envelope, onto the other phone.
    @Test func aCaptionRoundTripsToTheOtherPhone() throws {
        let mine = try context()
        let theirs = try context()

        let album = Album(name: "🎀", authorID: "me")
        album.caption = "你在，我在，就是海枯石烂。"
        mine.insert(album)
        try mine.save()

        SyncApply.apply(album.envelope(), in: theirs, localAuthorID: "them")
        try theirs.save()

        let arrived = try #require(try theirs.fetch(FetchDescriptor<Album>()).first)
        #expect(arrived.caption == "你在，我在，就是海枯石烂。")
    }
}
