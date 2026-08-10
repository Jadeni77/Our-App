import Foundation
import SwiftData

/// Reads and writes check-ins. Thin on purpose — it exists so no view
/// hand-rolls a predicate, and so these rules are testable without one.
@MainActor
enum CheckInStore {
    /// Checking in for a day you have already checked in on is a no-op, not a
    /// second row. Tapping twice is a mis-tap, never a second day.
    @discardableResult
    static func checkIn(in context: ModelContext,
                        authorID: String,
                        on day: Date = .now) -> CheckIn {
        let anchored = SpecialDateSchedule.anchor(for: day)
        let descriptor = FetchDescriptor<CheckIn>(
            predicate: #Predicate {
                $0.deletedAt == nil && $0.day == anchored && $0.authorID == authorID
            })
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let created = CheckIn(day: day, authorID: authorID)
        context.insert(created)
        try? context.save()
        return created
    }

    /// Every day this author has checked in, unordered — `SparkStreak` does the
    /// ordering, because that is where the rule is tested.
    static func days(in context: ModelContext, authorID: String) -> [Date] {
        let descriptor = FetchDescriptor<CheckIn>(
            predicate: #Predicate {
                $0.deletedAt == nil && $0.authorID == authorID
            })
        return (try? context.fetch(descriptor).map(\.day)) ?? []
    }
}
