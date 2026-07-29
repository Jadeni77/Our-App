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

    @Test func proposeManualTrimsAndUsesFallbackEmoji() {
        let flow = FoodDecisionFlow()
        flow.proposeManual("  Xinjiang BBQ  ")
        #expect(flow.phase == .deciding(Cuisine(name: "Xinjiang BBQ", emoji: "🍽️")))
    }

    @Test func proposeManualMatchesPoolEntryCaseInsensitively() {
        let flow = FoodDecisionFlow()
        flow.proposeManual("hotpot")
        #expect(flow.phase == .deciding(Cuisine(name: "Hotpot", emoji: "🍲")))
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

    @Test func agreePersistsARecordAndMovesToDecided() throws {
        let context = try makeContext()
        let flow = FoodDecisionFlow()
        flow.proposeManual("Ramen")
        flow.agree(in: context)

        #expect(flow.phase == .decided(Cuisine(name: "Ramen", emoji: "🍜")))
        let records = try context.fetch(FetchDescriptor<DecisionRecord>())
        #expect(records.map(\.cuisineChosen) == ["Ramen"])
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
