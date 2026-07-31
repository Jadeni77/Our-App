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

    // MARK: Slingshot
    static let maxPullDistance: CGFloat = 90
    /// Releases shorter than this reseat instead of flinging (accidental taps).
    static let minPullDistance: CGFloat = 14
    /// Launch speed per point of pull — velocity, not impulse, so the feel
    /// is mass-independent across characters.
    static let launchVelocityPerPoint: CGFloat = 8.5
    /// How far from the seat a touch may start and still grab the sprite.
    static let grabRadius: CGFloat = 60
    /// Levels 1..N show the dotted trajectory hint while aiming.
    static let trajectoryHintLevels = 3
    static let trajectoryDots = 8

    // MARK: Impulse calibration
    /// SpriteKit's collisionImpulse is kg·m/s (150 pt = 1 m), so real hits
    /// measure ~0.05–0.5. The damage model speaks in abstract units — this
    /// factor converts; raise it and the whole world gets more fragile.
    static let collisionImpulseScale: Double = 25

    // MARK: Flight & settle detection
    /// A launched sprite is spent after moving slower than spentSpeed for
    /// spentDuration, leaving the world, or flying longer than flightTimeout.
    static let spriteSpentSpeed: CGFloat = 20
    static let spriteSpentDuration: TimeInterval = 0.6
    static let flightTimeout: TimeInterval = 6
    /// The world has settled when every dynamic body is slower than
    /// settleSpeed for settleDuration (or the cap expires).
    static let settleSpeed: CGFloat = 12
    static let settleDuration: TimeInterval = 0.5
    static let settleTimeout: TimeInterval = 4
}
