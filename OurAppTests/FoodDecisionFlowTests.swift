import Testing
import SwiftData
@testable import OurApp

@MainActor
struct FoodDecisionFlowTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try Persistence.makeContainer(inMemory: true))
    }

    @Test func startsInProposePhase() {
        #expect(FoodDecisionFlow().phase == .propose)
    }

    @Test func proposeRandomMovesToDecidingWithAPoolCuisine() {
        let flow = FoodDecisionFlow()
        flow.proposeRandom()
        guard case .deciding(let cuisine) = flow.phase else {
            Issue.record("expected .deciding, got \(flow.phase)")
            return
        }
        #expect(CuisinePool.all.contains(cuisine))
    }

    @Test func proposeManualResolvesPoolEntryInAnyLanguage() {
        let flow = FoodDecisionFlow()
        flow.proposeManual("  火锅  ")
        guard case .deciding(let cuisine) = flow.phase else {
            Issue.record("expected .deciding, got \(flow.phase)")
            return
        }
        #expect(cuisine.id == "hotpot")
    }

    @Test func proposeManualKeepsUnknownTextAsCustom() {
        let flow = FoodDecisionFlow()
        flow.proposeManual("Xinjiang BBQ")
        guard case .deciding(let cuisine) = flow.phase else {
            Issue.record("expected .deciding, got \(flow.phase)")
            return
        }
        #expect(cuisine.isCustom)
        #expect(cuisine.displayName == "Xinjiang BBQ")
    }

    @Test func proposeManualIgnoresBlankInput() {
        let flow = FoodDecisionFlow()
        flow.proposeManual("   ")
        #expect(flow.phase == .propose)
    }

    @Test func rerollDrawsADifferentCuisineAndStaysDeciding() {
        let flow = FoodDecisionFlow()
        flow.proposeRandom()
        guard case .deciding(let first) = flow.phase else {
            Issue.record("expected .deciding, got \(flow.phase)")
            return
        }
        flow.reroll()
        guard case .deciding(let second) = flow.phase else {
            Issue.record("expected .deciding after reroll, got \(flow.phase)")
            return
        }
        #expect(second != first)
    }

    @Test func agreeOnPoolCuisineRecordsStableID() throws {
        let context = try makeContext()
        let flow = FoodDecisionFlow()
        flow.proposeManual("火锅")
        flow.agree(in: context)

        let records = try context.fetch(FetchDescriptor<DecisionRecord>())
        #expect(records.count == 1)
        #expect(records.first?.cuisineID == "hotpot")
        #expect(records.first?.cuisineChosen.isEmpty == false)
        guard case .decided(let cuisine) = flow.phase else {
            Issue.record("expected .decided, got \(flow.phase)")
            return
        }
        #expect(cuisine.id == "hotpot")
    }

    @Test func agreeOnCustomCuisineRecordsNilID() throws {
        let context = try makeContext()
        let flow = FoodDecisionFlow()
        flow.proposeManual("Xinjiang BBQ")
        flow.agree(in: context)

        let records = try context.fetch(FetchDescriptor<DecisionRecord>())
        #expect(records.first?.cuisineID == nil)
        #expect(records.first?.cuisineChosen == "Xinjiang BBQ")
    }

    @Test func legacyRecordsWithoutIDStillLoad() throws {
        let context = try makeContext()
        context.insert(DecisionRecord(cuisineChosen: "Hotpot"))
        try context.save()
        let records = try context.fetch(FetchDescriptor<DecisionRecord>())
        #expect(records.first?.cuisineID == nil)
        #expect(records.first?.cuisineChosen == "Hotpot")
    }

    @Test func agreeOutsideDecidingDoesNothing() throws {
        let context = try makeContext()
        let flow = FoodDecisionFlow()
        flow.agree(in: context)
        #expect(flow.phase == .propose)
        #expect(try context.fetch(FetchDescriptor<DecisionRecord>()).isEmpty)
    }

    @Test func startOverReturnsToPropose() {
        let flow = FoodDecisionFlow()
        flow.proposeRandom()
        flow.startOver()
        #expect(flow.phase == .propose)
    }
}
