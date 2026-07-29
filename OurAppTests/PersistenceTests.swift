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
}
