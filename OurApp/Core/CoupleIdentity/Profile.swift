import Foundation
import SwiftData

/// Who someone is, written by **them**.
///
/// The owner's objection, three times over: *"Why am I the one setting the name
/// and picture of my lover? That should be their profile, not mine."*
///
/// So a profile is **mirrored**, not shared (P19): each author owns their row
/// and the other phone stores and displays it and never writes it. That is a
/// stronger guarantee than shared — two authors never touch one record, so
/// there is nothing to merge and nothing to get wrong. It also means the
/// question "whose name is this?" has an answer in the data rather than in a
/// slot number that depends on which phone you are holding.
///
/// §7 hygiene throughout: a stable id, `updatedAt`, `authorID`, a `deletedAt`
/// tombstone, no `@Attribute(.unique)`, and every property defaulted — which is
/// what CloudKit mirroring requires and what a missing default once cost this
/// project on enrolment day.
@Model
final class Profile {
    var id: UUID = UUID()
    /// Whose profile this is. **Also its identity**: one row per person, so a
    /// second device belonging to the same person updates rather than adds.
    var authorID: String = ""
    var name: String = ""
    /// Keyed into the same photo store memories use, so one resizing and one
    /// sync path serves both.
    var photoID: String?
    /// How they would like to be referred to — theirs to say, not yours to
    /// guess. See `PartnerVoice`.
    var pronoun: String = PartnerVoice.Pronoun.they.rawValue
    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(authorID: String, name: String = "", photoID: String? = nil,
         pronoun: PartnerVoice.Pronoun = .they) {
        // The id *is* derived from the author, so two phones belonging to one
        // person converge on one row instead of racing to create two.
        self.id = Profile.id(for: authorID)
        self.authorID = authorID
        self.name = name
        self.photoID = photoID
        self.pronoun = pronoun.rawValue
        self.updatedAt = .now
    }

    /// A stable id from an author id, so the record has one identity across
    /// every device that ever writes it — the same trick that makes a co-op
    /// match's id its level's id.
    static func id(for authorID: String) -> UUID {
        UUID(uuidString: authorID) ?? UUID(
            uuidString: "00000000-0000-4000-8000-" + String(
                format: "%012x", abs(authorID.hashValue) % 0xFFFFFFFFFFFF)) ?? UUID()
    }

    var voice: PartnerVoice.Pronoun {
        PartnerVoice.Pronoun(rawValue: pronoun) ?? .they
    }

    static var visible: Predicate<Profile> {
        #Predicate<Profile> { $0.deletedAt == nil }
    }
}
