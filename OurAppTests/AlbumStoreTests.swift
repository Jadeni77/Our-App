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

    /// **A retired photo leaves the albums it was in.** Deleting a memory takes
    /// its files, so a membership still pointing at one is a square that can
    /// never load and a count nobody can reconcile with what's on screen.
    @Test func aMembershipWhosePhotoWasRetiredStopsCounting() throws {
        let store = try context()
        try library(store, ["kept", "gone"])
        let album = AlbumStore.create(name: "🎀", authorID: "me", in: store)
        AlbumStore.add(assetID: "kept", to: album, authorID: "me", in: store)
        AlbumStore.add(assetID: "gone", to: album, authorID: "me", in: store)
        AlbumStore.setCover(album, to: "gone", in: store)
        #expect(AlbumStore.count(of: album, in: store) == 2)

        let retired = try #require(try store.fetch(FetchDescriptor<Photo>())
            .first { $0.assetID == "gone" })
        retired.deletedAt = .now
        try store.save()

        #expect(AlbumStore.count(of: album, in: store) == 1)
        #expect(AlbumStore.assets(of: album, in: store) == ["kept"])
        // And the cover falls back rather than staying on a picture that isn't
        // a member any more — the rule `summary(of:)` already had, now reached
        // through the retirement filter too.
        #expect(AlbumStore.cover(of: album, in: store) == "kept")
    }

    /// **The other half, and the one that is easy to break while fixing the
    /// first.** A membership with *no* `Photo` row at all is not a retired
    /// photo — it is the normal case of the membership arriving before the
    /// picture, since the two are independent records. Treating an absent row
    /// like a tombstoned one would empty every album mid-sync.
    @Test func aMembershipWhosePhotoHasNotArrivedStillCounts() throws {
        let store = try context()
        let album = AlbumStore.create(name: "🎀", authorID: "me", in: store)
        // No `Photo` inserted for "early" on purpose.
        AlbumStore.add(assetID: "early", to: album, authorID: "them", in: store)

        #expect(AlbumStore.count(of: album, in: store) == 1)
        #expect(AlbumStore.assets(of: album, in: store) == ["early"])
        #expect(AlbumStore.cover(of: album, in: store) == "early")
    }

    /// **The rendering half of the invariant the test above already covers at
    /// the counting layer.** `AlbumDetailView` used to derive its whole grid
    /// straight from `Photo` rows once day-sections needed `takenAt` to know
    /// where a tile belonged — which silently dropped exactly this membership
    /// from the screen even though `count(of:)`, right above it, still
    /// counted it. `orphanedAssets` is the pure half of the fix: given the
    /// live member ids and whichever `Photo` rows are actually known, it
    /// names the ones with nothing behind them yet, so the view has something
    /// to render (and remove) instead of nothing at all.
    @Test func orphanedAssetsAreTheMembersWithNoMatchingPhoto() throws {
        let store = try context()
        try library(store, ["here"])
        let album = AlbumStore.create(name: "🎀", authorID: "me", in: store)
        AlbumStore.add(assetID: "here", to: album, authorID: "me", in: store)
        // No `Photo` row for "early" — the membership arrived, the picture
        // hasn't, same setup as the counting test above.
        AlbumStore.add(assetID: "early", to: album, authorID: "them", in: store)

        let memberAssetIDs = AlbumStore.assets(of: album, in: store)
        let knownPhotos = try store.fetch(FetchDescriptor<Photo>())

        #expect(AlbumStore.orphanedAssets(in: memberAssetIDs, notMatching: knownPhotos) == ["early"])
    }

    /// A member whose `Photo` row **has** arrived is not an orphan — the
    /// common case has to stay empty, or every album would grow a trailing
    /// strip of placeholders it doesn't need.
    @Test func noOrphansWhenEveryMemberHasAMatchingPhoto() throws {
        let store = try context()
        try library(store, ["a", "b"])
        let album = AlbumStore.create(name: "🎀", authorID: "me", in: store)
        AlbumStore.add(assetID: "a", to: album, authorID: "me", in: store)
        AlbumStore.add(assetID: "b", to: album, authorID: "me", in: store)

        let memberAssetIDs = AlbumStore.assets(of: album, in: store)
        let knownPhotos = try store.fetch(FetchDescriptor<Photo>())

        #expect(AlbumStore.orphanedAssets(in: memberAssetIDs, notMatching: knownPhotos).isEmpty)
    }
}

/// Two phones, one album.
@MainActor
struct AlbumConvergenceTests {
    private func context() throws -> ModelContext {
        ModelContext(try Persistence.makeContainer(inMemory: true))
    }

    /// One tick of sync in both directions: every membership either phone
    /// holds is offered to the other, which is what the real engine does and
    /// the only way a merge rule's *refusals* are visible at all.
    private func exchange(_ mine: ModelContext, _ theirs: ModelContext) throws {
        let fromMe = try mine.fetch(FetchDescriptor<AlbumEntry>()).map { $0.envelope() }
        let fromThem = try theirs.fetch(FetchDescriptor<AlbumEntry>()).map { $0.envelope() }
        for envelope in fromThem {
            SyncApply.apply(envelope, in: mine, localAuthorID: "me")
        }
        for envelope in fromMe {
            SyncApply.apply(envelope, in: theirs, localAuthorID: "them")
        }
        try mine.save()
        try theirs.save()
    }

    /// The same album on both phones, which is what the derived ids give us.
    private func sharedAlbum(_ mine: ModelContext,
                             _ theirs: ModelContext) throws -> (Album, Album) {
        let album = Album(name: "🎀", authorID: "me")
        mine.insert(album)
        let hers = Album(name: "🎀", authorID: "me")
        hers.id = album.id
        theirs.insert(hers)
        try mine.save()
        try theirs.save()
        return (album, hers)
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

    /// **Re-filing a photo after a removal has synced must reach both phones.**
    ///
    /// This is the failure that made `AlbumEntry` the documented exception to
    /// the sticky-tombstone rule (P21). With `verdict` in `applyAlbumEntry`,
    /// the last step below is where it broke: her row is tombstoned, so the
    /// envelope reviving mine was refused silently, my album read 1 and hers
    /// read 0 for good — the push watermark only moves forward, so that
    /// envelope never gets a second chance.
    ///
    /// Deliberately not a local-only test. Everything before the last exchange
    /// passed on the broken build; only two contexts trading envelopes both
    /// ways shows it.
    @Test func refilingAfterASyncedRemovalReachesBothPhones() throws {
        let mine = try context()
        let theirs = try context()
        let (album, hers) = try sharedAlbum(mine, theirs)

        AlbumStore.add(assetID: "a", to: album, authorID: "me", in: mine)
        try exchange(mine, theirs)
        #expect(AlbumStore.count(of: album, in: mine) == 1)
        #expect(AlbumStore.count(of: hers, in: theirs) == 1)

        // I take it out; the tombstone travels and her count follows.
        AlbumStore.remove(assetID: "a", from: album, in: mine)
        try exchange(mine, theirs)
        #expect(AlbumStore.count(of: album, in: mine) == 0)
        #expect(AlbumStore.count(of: hers, in: theirs) == 0)

        // Tomorrow I tap it again. One row, revived — and it must replicate.
        AlbumStore.add(assetID: "a", to: album, authorID: "me", in: mine)
        #expect(AlbumStore.count(of: album, in: mine) == 1)
        try exchange(mine, theirs)

        #expect(AlbumStore.count(of: album, in: mine) == 1)
        #expect(AlbumStore.count(of: hers, in: theirs) == 1)
        // Still one row each: reviving is a write to the membership that was
        // already there, never a second one that could never be reconciled.
        #expect(try mine.fetch(FetchDescriptor<AlbumEntry>()).count == 1)
        #expect(try theirs.fetch(FetchDescriptor<AlbumEntry>()).count == 1)
    }

    /// The other half of the exception: **a removal still wins when it is the
    /// newer write.** Dropping the tombstone gate must not make tombstones
    /// weightless — a photo she takes out after I put it in has to leave my
    /// album too, or "remove" is the action that silently does nothing.
    @Test func aNewerRemovalStillBeatsAnOlderAdd() throws {
        let mine = try context()
        let theirs = try context()
        let (album, hers) = try sharedAlbum(mine, theirs)

        AlbumStore.add(assetID: "a", to: album, authorID: "me", in: mine)
        try exchange(mine, theirs)

        AlbumStore.remove(assetID: "a", from: hers, in: theirs)
        try exchange(mine, theirs)

        #expect(AlbumStore.count(of: album, in: mine) == 0)
        #expect(AlbumStore.count(of: hers, in: theirs) == 0)
    }
}
