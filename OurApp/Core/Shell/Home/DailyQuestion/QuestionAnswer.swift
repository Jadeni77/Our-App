import Foundation
import SwiftData

/// One person's answer to one question on one day.
///
/// Rows are never reused across days, so history costs nothing — it is a query,
/// not a feature. Carries §7's hygiene from the first line so the CloudKit move
/// is mechanical: stable id, `updatedAt`, `authorID`, tombstone; no unique
/// constraint and every property defaulted, because SwiftData's CloudKit
/// mirroring rejects both.
@Model
final class QuestionAnswer {
    var id: UUID = UUID()
    /// The catalog's stable id, never an index — growing the catalog must not
    /// rewrite what a past answer was answering.
    var questionID: String = ""
    /// A floating civil day at noon UTC (H8), so two phones agree which day
    /// an answer belongs to.
    var day: Date = Date.now
    /// User data — stored verbatim, never translated.
    var text: String = ""
    /// `Partner.rawValue`. Empty only if written before a phone owner was set,
    /// which the UI prevents.
    var authorID: String = ""
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    init(questionID: String, day: Date, text: String, authorID: String) {
        self.id = UUID()
        self.questionID = questionID
        self.day = day
        self.text = text
        self.authorID = authorID
        self.updatedAt = .now
    }
}

extension QuestionAnswer {
    /// The one definition of "not deleted".
    static var visible: Predicate<QuestionAnswer> {
        #Predicate<QuestionAnswer> { $0.deletedAt == nil }
    }
}
