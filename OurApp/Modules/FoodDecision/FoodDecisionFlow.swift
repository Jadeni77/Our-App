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

    /// Manual entry. Matches a pool entry case-insensitively (to reuse its emoji);
    /// unknown cuisines get the fallback emoji. Blank input is ignored.
    func proposeManual(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let cuisine = CuisinePool.all.first { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
            ?? Cuisine(name: trimmed, emoji: "🍽️")
        phase = .deciding(cuisine)
    }

    func reroll() {
        guard case .deciding(let current) = phase else { return }
        phase = .deciding(CuisinePool.draw(excluding: current))
    }

    /// Agree seals the decision and silently records it (decision F4).
    /// The context comes from the view layer so the flow stays construction-free in tests.
    func agree(in context: ModelContext) {
        guard case .deciding(let cuisine) = phase else { return }
        context.insert(DecisionRecord(cuisineChosen: cuisine.name))
        try? context.save()
        phase = .decided(cuisine)
    }

    func startOver() {
        phase = .propose
    }
}
