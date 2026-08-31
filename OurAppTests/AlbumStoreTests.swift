import Foundation
import SwiftData
import Testing
@testable import OurApp

@MainActor
struct AlbumStoreTests {
    private func context() throws -> ModelContext {
        ModelContext(try Persistence.makeContainer(inMemory: true))
    }

    private func library(_ store: ModelContext, _ assets: [String]) throws {
        for asset in assets { store.insert(Photo(assetID: asset, authorID: "me")) }
        try store.save()
    }

    @Test func aPhotoCanBeInSeveralAlbumsAtOnce() throws {
        let store = try context()
        try library(store, ["a"])
        let bow = AlbumStore.create(name: "🎀", authorID: "me", in: store)
        let spring = AlbumStore.create(name: "2024·春", authorID: "me", in: store)

        AlbumStore.add(assetID: "a", to: bow, authorID: "me", in: store)
        AlbumStore.add(assetID: "a", to: spring, authorID: "me", in: store)

        #expect(AlbumStore.count(of: bow, in: store) == 1)
        #expect(AlbumStore.count(of: spring, in: store) == 1)
    }

    /// Filing the same picture twice — which two phones will do — is one
    /// membership, because the id is the album and the asset.
    @Test func filingTwiceIsStillOneMembership() throws {
        let store = try context()
        try library(store, ["a"])
        let album = AlbumStore.create(name: "🎀", authorID: "me", in: store)

        AlbumStore.add(assetID: "a", to: album, authorID: "me", in: store)
        AlbumStore.add(assetID: "a", to: album, authorID: "them", in: store)

        #expect(AlbumStore.count(of: album, in: store) == 1)
    }

    /// **Taking a photo out of an album keeps the photo**, and keeps its other
    /// albums. Anything else would make filing frightening.
    @Test func removingFromAnAlbumKeepsThePhotoAndItsOtherAlbums() throws {
        let store = try context()
        try library(store, ["a"])
        let bow = AlbumStore.create(name: "🎀", authorID: "me", in: store)
        let spring = AlbumStore.create(name: "2024·春", authorID: "me", in: store)
        AlbumStore.add(assetID: "a", to: bow, authorID: "me", in: store)
        AlbumStore.add(assetID: "a", to: spring, authorID: "me", in: store)

        AlbumStore.remove(assetID: "a", from: bow, in: store)

        #expect(AlbumStore.count(of: bow, in: store) == 0)
        #expect(AlbumStore.count(of: spring, in: store) == 1)
        #expect(PhotoLibrary.all(in: store).count == 1)
    }

    /// Deleting an album is deleting a *label*.
    @Test func deletingAnAlbumKeepsEveryPhotoItHeld() throws {
        let store = try context()
        try library(store, ["a", "b"])
        let album = AlbumStore.create(name: "TBD", authorID: "me", in: store)
        AlbumStore.add(assetID: "a", to: album, authorID: "me", in: store)
        AlbumStore.add(assetID: "b", to: album, authorID: "me", in: store)

        AlbumStore.delete(album, in: store)

        #expect(AlbumStore.albums(in: store).isEmpty)
        #expect(PhotoLibrary.all(in: store).count == 2)
    }

    /// A new album is never a blank square: the newest member stands in until
    /// somebody chooses.
    @Test func theCoverFallsBackToTheNewestMember() throws {
        let store = try context()
        try library(store, ["old", "new"])
        let album = AlbumStore.create(name: "🎀", authorID: "me", in: store)
        AlbumStore.add(assetID: "old", to: album, authorID: "me", in: store)
        AlbumStore.add(assetID: "new", to: album, authorID: "me", in: store)

        #expect(AlbumStore.cover(of: album, in: store) == "new")

        AlbumStore.setCover(album, to: "old", in: store)
        #expect(AlbumStore.cover(of: album, in: store) == "old")
    }

    /// An empty album has no cover to offer, and must say so rather than
    /// inventing one.
    @Test func anEmptyAlbumHasNoCover() throws {
        let store = try context()
        let album = AlbumStore.create(name: "empty", authorID: "me", in: store)
        #expect(AlbumStore.cover(of: album, in: store) == nil)
        #expect(AlbumStore.count(of: album, in: store) == 0)
    }

    /// Counts follow tombstones. A stored number is a number that drifts, and
    /// every running total this project has kept has had to be removed.
    @Test func countsAreDerivedNotStored() throws {
        let store = try context()
        try library(store, ["a"])
        let album = AlbumStore.create(name: "🎀", authorID: "me", in: store)
        AlbumStore.add(assetID: "a", to: album, authorID: "me", in: store)
        #expect(AlbumStore.count(of: album, in: store) == 1)

        AlbumStore.remove(assetID: "a", from: album, in: store)
        #expect(AlbumStore.count(of: album, in: store) == 0)
    }
}

/// Two phones, one album.
@MainActor
struct AlbumConvergenceTests {
    private func context() throws -> ModelContext {
        ModelContext(try Persistence.makeContainer(inMemory: true))
    }

    /// **The property the whole design rests on.** Both of you filing one
    /// picture into one album, from different phones, must converge on a single
    /// membership — not two rows that can never be reconciled, which is what
    /// left co-op matches duplicated and both players waiting.
    @Test func bothPhonesFilingOnePhotoConvergeOnOneMembership() throws {
        let mine = try context()
        let theirs = try context()

        let album = Album(name: "🎀", authorID: "me")
        mine.insert(album)
        let hers = Album(name: "🎀", authorID: "me")
        hers.id = album.id
        theirs.insert(hers)
        try mine.save(); try theirs.save()

        AlbumStore.add(assetID: "a", to: album, authorID: "me", in: mine)
        AlbumStore.add(assetID: "a", to: hers, authorID: "them", in: theirs)

        // Each phone now sends its membership to the other.
        let fromMe = try #require(try mine.fetch(FetchDescriptor<AlbumEntry>()).first)
        let fromThem = try #require(try theirs.fetch(FetchDescriptor<AlbumEntry>()).first)
        SyncApply.apply(fromThem.envelope(), in: mine, localAuthorID: "me")
        SyncApply.apply(fromMe.envelope(), in: theirs, localAuthorID: "them")
        try mine.save(); try theirs.save()

        #expect(try mine.fetch(FetchDescriptor<AlbumEntry>()).count == 1)
        #expect(try theirs.fetch(FetchDescriptor<AlbumEntry>()).count == 1)
        #expect(AlbumStore.count(of: album, in: mine) == 1)
    }
}
