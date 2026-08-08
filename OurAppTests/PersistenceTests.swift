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
        #expect(dates.first?.authorID == nil)
    }
}
