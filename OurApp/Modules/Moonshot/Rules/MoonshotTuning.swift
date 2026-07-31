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

    // MARK: Scene (design canvas — every phone sees this world via aspectFit)
    static let sceneSize = CGSize(width: 840, height: 390)
    /// Scene-space y of the ground top; level y=0 maps here.
    static let groundY: CGFloat = 40
    static let slingshotX: CGFloat = 110
    /// Fork height above the ground — also where the loaded sprite sits.
    static let slingshotHeight: CGFloat = 90
    /// Authored positions may drop a point or two — let the world settle
    /// before input unlocks so the fort never wobbles under the first aim.
    static let settlePauseAfterBuild: TimeInterval = 0.5
}
