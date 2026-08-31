import Foundation
import SwiftData
import Testing
@testable import OurApp

/// A profile is written by the person it describes.
@MainActor
struct ProfileSyncTests {
    private let me = "author-a"
    private let her = "author-b"

    private func context() throws -> ModelContext {
        ModelContext(try Persistence.makeContainer(inMemory: true))
    }

    /// The owner's objection, answered: their name arrives from their phone.
    @Test func theirProfileArrivesAndIsStored() throws {
        let store = try context()
        let hers = Profile(authorID: her, name: "Jade", pronoun: .she)

        SyncApply.apply(hers.envelope(), in: store, localAuthorID: me)
        try store.save()

        let arrived = try #require(try store.fetch(FetchDescriptor<Profile>()).first)
        #expect(arrived.name == "Jade")
        #expect(arrived.voice == .she)
        #expect(arrived.authorID == her)
    }

    /// **This phone is the authority on you.** A remote copy of your own row is
    /// either your own write coming back or something not to be honoured;
    /// either way it must not overwrite what you typed.
    @Test func nobodyElseCanRewriteYourOwnProfile() throws {
        let store = try context()
        let mine = Profile(authorID: me, name: "Xiaobin")
        store.insert(mine)
        try store.save()

        var forged = mine.envelope()
        forged.fields["name"] = .string("Not my name")
        forged.updatedAt = .now.addingTimeInterval(3600)
        #expect(SyncApply.apply(forged, in: store, localAuthorID: me) == false)
        #expect(mine.name == "Xiaobin")
    }

    /// One row per person: a second device of theirs updates rather than adds,
    /// because the id is derived from the author.
    @Test func onePersonHasOneRow() throws {
        let store = try context()
        let first = Profile(authorID: her, name: "Jade")
        let second = Profile(authorID: her, name: "Jade on the iPad")
        second.updatedAt = .now.addingTimeInterval(60)

        SyncApply.apply(first.envelope(), in: store, localAuthorID: me)
        SyncApply.apply(second.envelope(), in: store, localAuthorID: me)
        try store.save()

        let all = try store.fetch(FetchDescriptor<Profile>())
        #expect(all.count == 1)
        #expect(all.first?.name == "Jade on the iPad")
    }

    /// Clearing a photo is a thing somebody can choose to do.
    @Test func aRemovedPhotoIsRemovedHereToo() throws {
        let store = try context()
        let hers = Profile(authorID: her, name: "Jade", photoID: "pic-1")
        SyncApply.apply(hers.envelope(), in: store, localAuthorID: me)

        hers.photoID = nil
        hers.updatedAt = .now.addingTimeInterval(60)
        SyncApply.apply(hers.envelope(), in: store, localAuthorID: me)
        try store.save()

        #expect(try store.fetch(FetchDescriptor<Profile>()).first?.photoID == nil)
    }

    /// Every property defaulted, or CloudKit mirroring refuses the store — the
    /// mistake that would have bricked the app on enrolment day.
    @Test func itSatisfiesTheCloudKitRules() throws {
        let store = try context()
        let bare = Profile(authorID: her)
        store.insert(bare)
        try store.save()
        #expect(bare.name.isEmpty)
        #expect(bare.voice == .they)
        #expect(bare.deletedAt == nil)
    }
}

/// The record has to exist before it can travel.
@MainActor
struct ProfileSeedingTests {
    private func context() throws -> ModelContext {
        ModelContext(try Persistence.makeContainer(inMemory: true))
    }

    /// **Created at launch, not on first visit.** It used to be made lazily
    /// inside the profile sheet, so a phone whose owner never tapped their own
    /// face had no record to send — one phone showed a name the other had
    /// never heard of, and nothing anywhere said why.
    @Test func openingTheAppIsEnoughToHaveAProfile() throws {
        let store = try context()
        #expect(try store.fetch(FetchDescriptor<Profile>()).isEmpty)

        ProfileStore.mine(in: store)
        #expect(try store.fetch(FetchDescriptor<Profile>()).count == 1)
    }

    /// Asked twice, it is still one profile — otherwise every launch would add
    /// another row claiming to be you.
    @Test func seedingIsIdempotent() throws {
        let store = try context()
        let first = ProfileStore.mine(in: store)
        let second = ProfileStore.mine(in: store)
        #expect(first === second)
        #expect(try store.fetch(FetchDescriptor<Profile>()).count == 1)
    }

    /// A name typed into the old Settings screen moves into the record rather
    /// than being abandoned there. That data was never wrong — it was only
    /// stored in the wrong place.
    @Test func whatYouAlreadyTypedIsCarriedOver() throws {
        let store = try context()
        let suite = "profile.seed.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let identity = CoupleIdentityStore(defaults: defaults)
        identity.nameOne = "Xiaobin"

        #expect(ProfileStore.mine(in: store, seedingFrom: identity).name == "Xiaobin")
    }

    /// Theirs is never invented here. An empty row we made up for them would be
    /// indistinguishable from one they wrote, and "they have not set this up
    /// yet" is a real state worth being able to see.
    @Test func theirProfileIsNeverFabricated() throws {
        let store = try context()
        ProfileStore.mine(in: store)
        #expect(ProfileStore.partner(in: store) == nil)
    }
}
