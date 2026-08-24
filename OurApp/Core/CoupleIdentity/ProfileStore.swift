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
        guard let partner = SyncSecretStore.partnerAuthorID() else { return nil }
        return profile(for: partner, in: context)
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
