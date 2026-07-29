import Foundation
import Observation
import SwiftData

/// The decide-together state machine: propose → deciding → decided.
/// Pure logic, no UI — views render `phase` and call the transitions.
@MainActor
@Observable
final class FoodDecisionFlow {
    enum Phase: Equatable {
        case propose
        case deciding(Cuisine)
        case decided(Cuisine)
    }

    private(set) var phase: Phase = .propose

    func proposeRandom() {
        phase = .deciding(CuisinePool.draw())
    }

    /// Manual entry resolves across every language and search term (F6):
    /// 火锅 / Hotpot / 麻辣火锅 all land on the pool entry; unknown text stays
    /// as a free-form custom cuisine, exactly like v1.
    func proposeManual(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        phase = .deciding(CuisinePool.match(trimmed) ?? .custom(trimmed))
    }

    func reroll() {
        guard case .deciding(let current) = phase else { return }
        phase = .deciding(CuisinePool.draw(excluding: current))
    }

    /// Agree seals the decision and silently records it (F4), now with the
    /// stable id so history is language-proof (F6).
    func agree(in context: ModelContext) {
        guard case .deciding(let cuisine) = phase else { return }
        context.insert(DecisionRecord(
            cuisineChosen: cuisine.displayName,
            cuisineID: cuisine.isCustom ? nil : cuisine.id
        ))
        try? context.save()
        phase = .decided(cuisine)
    }

    func startOver() {
        phase = .propose
    }
}
