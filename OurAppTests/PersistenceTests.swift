import Foundation
import Testing
import SwiftData
@testable import OurApp

struct PersistenceTests {
    @Test func savesAndFetchesDecisionRecords() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = ModelContext(container)

        context.insert(DecisionRecord(cuisineChosen: "Hotpot"))
        try context.save()

        let records = try context.fetch(FetchDescriptor<DecisionRecord>())
        #expect(records.count == 1)
        #expect(records.first?.cuisineChosen == "Hotpot")
    }

    @Test func savesAndFetchesSpecialDates() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = ModelContext(container)

        context.insert(SpecialDate(title: "Her birthday",
                                   emoji: "🎂",
                                   date: Date(timeIntervalSinceReferenceDate: 800_000_000),
                                   repeatsYearly: true))
        try context.save()

        let dates = try context.fetch(FetchDescriptor<SpecialDate>())
        #expect(dates.count == 1)
        #expect(dates.first?.title == "Her birthday")
        #expect(dates.first?.repeatsYearly == true)
        // Soft-delete tombstone starts empty — a fresh date is not deleted.
        #expect(dates.first?.deletedAt == nil)
        // Was `== nil`, which pinned a bug in place: nothing on any write path
        // set an author, so the LWW tiebreak (which breaks on `authorID`) had
        // nothing to break on and two phones could disagree forever.
        #expect(dates.first?.authorID == LocalAuthor.id())
    }

    /// The edit-then-delete round trip the page performs, checked at the store
    /// rather than through the UI: a tombstoned row must disappear from the
    /// page's query while still existing in the store (H6 — the tombstone is
    /// what survives to the other phone when sync lands).
    @Test func editingUpdatesTheRowAndDeletingOnlyTombstonesIt() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let anchor = Date(timeIntervalSinceReferenceDate: 800_000_000)

        let date = SpecialDate(title: "Kyoto trip", emoji: "✈️", date: anchor)
        context.insert(date)
        try context.save()

        // The exact predicate SpecialDatesView and SpecialDatesBadge query with.
        let visible = FetchDescriptor<SpecialDate>(
            predicate: #Predicate { $0.deletedAt == nil })

        date.title = "Kyoto trip ✨"
        date.repeatsYearly = true
        date.updatedAt = .now
        try context.save()

        let afterEdit = try context.fetch(visible)
        #expect(afterEdit.count == 1)
        #expect(afterEdit.first?.title == "Kyoto trip ✨")
        #expect(afterEdit.first?.repeatsYearly == true)

        date.deletedAt = .now
        try context.save()

        #expect(try context.fetch(visible).isEmpty)
        // Still there — deleted, not gone.
        #expect(try context.fetchCount(FetchDescriptor<SpecialDate>()) == 1)
    }
}
