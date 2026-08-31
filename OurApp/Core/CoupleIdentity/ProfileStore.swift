import Foundation
import SwiftData
import UIKit

/// Reading and writing the two profiles, so no view invents its own lookup.
@MainActor
enum ProfileStore {
    /// Yours, created on first use.
    ///
    /// Seeded from whatever you had already typed into Settings, so upgrading
    /// does not silently blank the name and photo you set months ago. That data
    /// was never wrong — it was only ever stored in the wrong place.
    @discardableResult
    static func mine(in context: ModelContext,
                     seedingFrom identity: CoupleIdentityStore? = nil) -> Profile {
        let author = LocalAuthor.id()
        if let existing = profile(for: author, in: context) { return existing }

        let created = Profile(authorID: author)
        if let identity {
            created.name = identity.nameOne
            if let image = identity.avatars[.one],
               let data = image.jpegData(compressionQuality: 0.9) {
                created.photoID = try? MemoryPhotoStore().save(data)
            }
        }
        context.insert(created)
        try? context.save()
        return created
    }

    /// Theirs, if they have sent it. **Never created here**: an empty row we
    /// invented for them would be indistinguishable from one they wrote, and
    /// "they haven't set this up yet" is a real state worth being able to see.
    static func partner(in context: ModelContext) -> Profile? {
        let all = (try? context.fetch(FetchDescriptor<Profile>(predicate: Profile.visible))) ?? []
        if let paired = SyncSecretStore.partnerAuthorID(),
           let known = all.first(where: { $0.authorID == paired }) {
            return known
        }
        // **Any profile that is not yours.**
        //
        // Asking the pairing secret alone was too fragile: a phone can hold
        // their profile and still not know their author id — the secret lives
        // in the keychain and can be cleared, re-paired, or lost to a reinstall
        // while the records survive. That produced a phone displaying "My love"
        // over a row that had their name in it.
        //
        // A profile only ever arrives from the person you sync with, and there
        // is only ever one of them, so the record is its own evidence. It also
        // means the greeting no longer depends on a second piece of state
        // staying in step with the first.
        let me = LocalAuthor.id()
        return all.first { $0.authorID != me }
    }

    /// Whether this phone knows who the other person is at all.
    ///
    /// **Not "is the keychain secret present".** That secret can be cleared by
    /// a reinstall, a re-pair, or a restore while every record the two of you
    /// have exchanged survives — leaving a phone that offers to invite someone
    /// it is already syncing with, next to a phone that knows better. Two
    /// devices in one relationship gave different answers to the same question.
    ///
    /// Knowing their author id is the honest test: it means something of theirs
    /// has actually arrived here.
    static func isConnected(in context: ModelContext) -> Bool {
        partnerAuthorID(in: context) != nil
    }

    /// Who the other person is, by the same robust answer `partner` uses.
    ///
    /// The one question, asked once. Reading the keychain directly is what left
    /// 火花 counting a solo streak on a phone that had lost its pairing secret
    /// but still held every one of their check-ins — the number would have gone
    /// up while they were away, which is the exact bug it was just fixed for.
    static func partnerAuthorID(in context: ModelContext) -> String? {
        SyncSecretStore.partnerAuthorID() ?? partner(in: context)?.authorID
    }

    private static func profile(for authorID: String, in context: ModelContext) -> Profile? {
        let all = try? context.fetch(FetchDescriptor<Profile>(predicate: Profile.visible))
        return all?.first { $0.authorID == authorID }
    }

    static func image(for profile: Profile?) -> UIImage? {
        guard let id = profile?.photoID else { return nil }
        return MemoryPhotoStore().image(for: id)
    }

    /// Replaces your picture, keyed into the same store memories use — one
    /// resizing path and one sync path serving both.
    static func setPhoto(_ data: Data, on profile: Profile, in context: ModelContext) {
        guard let id = try? MemoryPhotoStore().save(data) else { return }
        profile.photoID = id
        profile.updatedAt = .now
        try? context.save()
    }
}
