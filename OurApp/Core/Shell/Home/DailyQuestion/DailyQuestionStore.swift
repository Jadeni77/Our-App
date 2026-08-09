import Foundation
import SwiftData

/// Reads and writes answers. Thin on purpose — it exists so the page never
/// hand-rolls a predicate, and so these rules are testable without a view.
@MainActor
enum DailyQuestionStore {
    /// One row per (question, day, author). Anchored so the lookup matches
    /// whatever time of day the caller happened to pass.
    static func answer(in context: ModelContext,
                       questionID: String,
                       day: Date,
                       author: Partner) -> QuestionAnswer? {
        let anchored = SpecialDateSchedule.anchor(for: day)
        let authorID = author.rawValue
        let descriptor = FetchDescriptor<QuestionAnswer>(
            predicate: #Predicate {
                $0.deletedAt == nil
                    && $0.questionID == questionID
                    && $0.day == anchored
                    && $0.authorID == authorID
            })
        return try? context.fetch(descriptor).first
    }

    /// Writes today's answer, updating the existing row rather than adding a
    /// second one — the same person answering the same question on the same day
    /// is an edit, not a new answer.
    @discardableResult
    static func write(_ text: String,
                      in context: ModelContext,
                      questionID: String,
                      day: Date,
                      author: Partner) -> QuestionAnswer {
        if let existing = answer(in: context, questionID: questionID,
                                 day: day, author: author) {
            existing.text = text
            existing.updatedAt = .now
            try? context.save()
            return existing
        }
        let created = QuestionAnswer(questionID: questionID,
                                     day: SpecialDateSchedule.anchor(for: day),
                                     text: text,
                                     authorID: author.rawValue)
        context.insert(created)
        try? context.save()
        return created
    }

    /// Every visible answer, newest day first.
    static func history(from context: ModelContext) throws -> [QuestionAnswer] {
        try context.fetch(FetchDescriptor<QuestionAnswer>(
            predicate: QuestionAnswer.visible,
            sortBy: [SortDescriptor(\.day, order: .reverse)]))
    }
}
