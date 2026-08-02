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
    /// Divides (impulse − threshold) into HP damage; smaller = more brutal
    /// world. Calibrated with the floaty gravity: a full-pull mochi lands
    /// ≈ 8.6 impulse units — cascading debris topples structures more than
    /// it shatters them.
    static let damageScale: Double = 3
    /// Gloom toughness (device-pass ruling 2026-07-31: they died to a touch).
    /// Grazes below bruise do nothing; bruise-to-instant hits cost 1 HP;
    /// instant and above pops outright — a clean direct hit still one-shots.
    /// Calibration anchors at g −5.5 / launch 9: a soft-pull split twin
    /// knocks at ~1.6–1.7 and a column-top fall lands ~1.9 — both must
    /// bruise (never shrug) or L7's knock-them-off solution deals no
    /// damage, so the floor sits at 1.5 with real margin; a full-pull
    /// mochi (~8.6) still one-shots. 1.5 was the old one-touch POP
    /// threshold — as a 2-HP bruise floor it can't bring that bug back.
    static let gloomHP = 2
    static let gloomBruiseImpulse: Double = 1.5
    static let gloomInstantPopImpulse: Double = 5.0
    /// Helmet (M36): a contact point higher than the gloom's center plus
    /// this brim counts as "from above" and deals nothing — roughly the
    /// top third of a radius-16 face, so grazing side hits stay lethal.
    static let helmetBrimY: CGFloat = 5

    // MARK: Scene (design canvas — every phone sees this world via aspectFit)
    static let sceneSize = CGSize(width: 840, height: 390)
    /// The floor extends this far past both visible edges (device-pass
    /// ruling 2026-07-31: no side walls — overshooting flings sail off-screen
    /// instead of bouncing back; shoved debris comes to rest out of sight).
    static let floorOverhang: CGFloat = 1000
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
    /// is mass-independent across characters. Paired with the floaty gravity
    /// above: 9/pt at g −5.5 arcs ~795pt at full pull (the whole world)
    /// while flying visibly slower than the rejected fast-and-flat 12/pt.
    static let launchVelocityPerPoint: CGFloat = 9
    /// How far from the seat a touch may start and still grab the sprite.
    static let grabRadius: CGFloat = 60
    /// Levels 1..N show the dotted trajectory hint while aiming.
    static let trajectoryHintLevels = 3
    static let trajectoryDots = 8

    // MARK: Physics feel
    /// World gravity in m/s² (SpriteKit's unit; 150 pt = 1 m). The scene sets
    /// this explicitly AND the trajectory hint samples it — one knob, never two.
    /// Deliberately floaty (device-pass ruling 2026-07-31: "it flies too
    /// fast"): the genre's long lazy arcs come from LOW gravity at moderate
    /// launch speed, not from raw velocity — same full-world range, slower
    /// graceful flight, and towers topple cinematically instead of snapping down.
    static let gravityMetersPerSecond: CGFloat = -5.5
    static let pieceFriction: CGFloat = 0.8
    // Piece restitution is per-material (Material.restitution — M20).
    static let gloomDensity: CGFloat = 0.8
    static let gloomFriction: CGFloat = 0.9
    static let gloomRestitution: CGFloat = 0.05
    // Sprite radius/density are per-character (MoonshotCharacters.swift).
    static let spriteFriction: CGFloat = 0.6
    static let spriteRestitution: CGFloat = 0.2
    static let groundFriction: CGFloat = 0.9
    /// Seconds between trajectory-hint dots — spaced for the floaty arcs
    /// (flights run ~1.4s at full pull; the dots should sketch most of it).
    static let trajectorySampleStep: TimeInterval = 0.15

    // MARK: Abilities (tap-triggered, one per flight)
    /// Moon Slam: horizontal motion dies, the drop hits this hard. Must
    /// clear meteorstone's impact threshold — the slam is stone's counter (M7).
    static let slamVerticalVelocity: CGFloat = -1600
    /// Comet Dash: current speed multiplies by this along the flight line.
    static let dashSpeedMultiplier: CGFloat = 2.2
    /// Split: the twins fan out this far either side of the flight line.
    static let splitAngle: CGFloat = .pi / 15
    /// Each twin keeps this fraction of the original mass.
    static let splitMassScale: CGFloat = 0.6
    /// Twins render (and collide) at this scale of a full twinkle…
    static let splitTwinScale: CGFloat = 0.8
    /// …and spawn this far either side of the flight line.
    static let splitSpawnOffset: CGFloat = 6
    /// Gravity Well: how long Nox pulls, how hard, and how far.
    static let wellDuration: TimeInterval = 1.0
    static let wellStrength: Float = 7
    static let wellRadius: Float = 220
    /// Phase: a mist that never enters a piece re-solidifies after this —
    /// a ghost drifting forever would break spent detection's promises.
    static let phaseTimeout: TimeInterval = 1.5

    // MARK: Gloom kinds (M29)
    /// The Great Gloom: a boss that chips, never pops in one.
    static let greatGloomHP = 5
    static let greatGloomScale: CGFloat = 3.0
    static let greatGloomDensity: CGFloat = 8.0
    /// Hoppers dodge: trigger distance to a landing sprite, cooldown
    /// between hops, and the hop's velocity components.
    static let hopperTriggerRadius: CGFloat = 100
    static let hopperCooldown: TimeInterval = 1.2
    static let hopperHopVertical: CGFloat = 520
    static let hopperHopLateral: CGFloat = 260
    /// How far a full hop carries sideways (~1.25 s of air at 260 pt/s,
    /// less damping) — the in-world check that keeps a dodge from
    /// leaping across the escape sweep.
    static let hopperHopCarry: CGFloat = 330

    // MARK: Moondust (M31)
    /// Dust per point of wreckage cost, the first-clear bonus, and the
    /// price of a repeat fling swap (the first pick each level is free).
    static let moondustPerCost = 1
    static let moondustFirstClear = 20
    static let moondustSwapPrice = 25
    /// Nox is summoned, never owned (M34, owner: "too OP"): every pick
    /// costs this — no free first, no permanent access. Levels that
    /// author him into their queue still hand him over for free.
    static let noxSummonPrice = 40

    // MARK: Rubber creaks (M34)
    /// Pull-distance fractions where the stretch ticks — derived from
    /// maxPullDistance so retuning the pull keeps all three bands alive.
    static let creakBandFractions: [CGFloat] = [1.0 / 3.0, 0.61, 0.87]

    // MARK: Impulse calibration
    /// SpriteKit's collisionImpulse is kg·m/s (150 pt = 1 m), so real hits
    /// measure ~0.05–0.5. The damage model speaks in abstract units — this
    /// factor converts; raise it and the whole world gets more fragile.
    static let collisionImpulseScale: Double = 25

    // MARK: Flight & settle detection
    /// A launched sprite is spent after moving slower than spentSpeed for
    /// spentDuration, leaving the world, or flying longer than flightTimeout.
    static let spriteSpentSpeed: CGFloat = 30
    static let spriteSpentDuration: TimeInterval = 0.5
    /// Restored on a sprite's FIRST contact: flight runs at zero damping so
    /// the arc matches the trajectory hint, but after impact the hint has
    /// kept its promise — without this, sprites skated for seconds
    /// (device-pass ruling 2026-07-31).
    static let spriteLandedLinearDamping: CGFloat = 1.2
    static let spriteLandedAngularDamping: CGFloat = 1.0
    static let flightTimeout: TimeInterval = 6
    /// The world has settled when every dynamic body is slower than
    /// settleSpeed for settleDuration (or the cap expires).
    static let settleSpeed: CGFloat = 12
    static let settleDuration: TimeInterval = 0.5
    static let settleTimeout: TimeInterval = 4
}
