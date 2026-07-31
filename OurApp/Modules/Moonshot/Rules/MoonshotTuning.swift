import Foundation

/// Every Moonshot gameplay number lives here (module doc, open questions):
/// tuning happens by editing a named constant, never a literal inside the
/// Engine or Rules.
enum MoonshotTuning {
    // MARK: World (points; design canvas is 840 wide, y measured up from ground top)
    static let worldWidth: CGFloat = 840
    static let gloomRadius: CGFloat = 16

    // MARK: 1v1 base building (M8 — identical budgets, priced pieces)
    static let baseBudget = 60
    static let baseGloomCount = 3

    // MARK: Destruction
    /// Divides (impulse − threshold) into HP damage; smaller = more brutal world.
    static let damageScale: Double = 3
    /// Contact impulse above which a Gloom pops.
    static let gloomPopImpulse: Double = 1.5
}
