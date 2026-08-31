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

    /// Every property defaulted, or CloudKit mirroring refuses the store.
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
}
