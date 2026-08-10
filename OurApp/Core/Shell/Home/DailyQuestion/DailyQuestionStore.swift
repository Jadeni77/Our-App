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
                       authorID: String) -> QuestionAnswer? {
        let anchored = SpecialDateSchedule.anchor(for: day)
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
                      authorID: String) -> QuestionAnswer {
        if let existing = answer(in: context, questionID: questionID,
                                 day: day, authorID: authorID) {
            existing.text = text
            existing.updatedAt = .now
            try? context.save()
            return existing
        }
        let created = QuestionAnswer(questionID: questionID,
                                     day: SpecialDateSchedule.anchor(for: day),
                                     text: text,
                                     authorID: authorID)
        context.insert(created)
        try? context.save()
        return created
    }

    /// Whether the tile should nag. Pure and static precisely so it can be
    /// tested — the same rule living inside a view's `onChange` closure is how
    /// the first version shipped a badge that never turned on.
    static func isUnanswered(_ answers: [QuestionAnswer],
                             by authorID: String,
                             on day: Date = .now) -> Bool {
        // No "before setup" case any more: this phone always has an id (P18),
        // so the badge has one fewer state in which it silently can't turn on.
        let anchored = SpecialDateSchedule.anchor(for: day)
        let questionID = DailyQuestionCatalog.question(on: day).id
        return !answers.contains {
            $0.deletedAt == nil
                && $0.questionID == questionID
                && $0.day == anchored
                && $0.authorID == authorID
        }
    }

    /// Every visible answer, newest day first.
    static func history(from context: ModelContext) throws -> [QuestionAnswer] {
        try context.fetch(FetchDescriptor<QuestionAnswer>(
            predicate: QuestionAnswer.visible,
            sortBy: [SortDescriptor(\.day, order: .reverse)]))
    }
}
