import SpriteKit
import SwiftUI

/// Physics collision categories — one bit each, contacts tested across all.
enum PhysicsCategory {
    static let sprite: UInt32 = 1 << 0
    static let piece: UInt32 = 1 << 1
    static let gloom: UInt32 = 1 << 2
    static let ground: UInt32 = 1 << 3
    /// A phasing Misty (M22). SpriteKit collision masks are per-body and
    /// ONE-WAY — clearing piece from HER mask alone would leave the piece
    /// side still resolving the collision, turning the mist into a
    /// zero-damage battering ram (review finding). Pieces exclude this
    /// category explicitly, making the pass-through two-sided.
    static let mist: UInt32 = 1 << 4
}

/// Field categories (M21): wind moves ONLY flying sprites — pieces and
/// glooms mask it out so forts never creep and settle detection stays
/// untouched. Nox's well hauls everything.
enum FieldCategory {
    static let wind: UInt32 = 1 << 0
    static let well: UInt32 = 1 << 1
}

/// A structure piece with material HP. Damage crosses two thresholds:
/// half HP shows the crack overlay once, zero removes the piece.
final class PieceNode: SKSpriteNode {
    enum Fate { case intact, cracked, destroyed }

    let material: Material
    private(set) var hp: Double
    private var showedCrack = false

    init(piece: MoonshotLevel.Piece) {
        material = piece.material
        hp = piece.material.hp
        let size = piece.shape.size
        super.init(texture: SpriteFactory.pieceTexture(shape: piece.shape, material: piece.material),
                   color: .clear, size: size)
        zRotation = piece.rotation
        name = "piece"

        let body = SKPhysicsBody(rectangleOf: size)
        body.density = piece.material.density
        body.friction = MoonshotTuning.pieceFriction
        body.restitution = piece.material.restitution   // cloudfoam is the springboard (M20)
        body.isDynamic = piece.material != .frame
        body.fieldBitMask = FieldCategory.well
        body.categoryBitMask = PhysicsCategory.piece
        body.collisionBitMask = ~PhysicsCategory.mist   // the mist passes; flesh collides
        body.contactTestBitMask = PhysicsCategory.sprite | PhysicsCategory.piece | PhysicsCategory.ground
        physicsBody = body
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    func applyDamage(_ damage: Double) -> Fate {
        // Idempotency latch: one physics step can queue several contacts for
        // the same piece — only the killing blow may report .destroyed, or
        // demolition scoring (slice c) and audio (PR 5) double-count.
        guard damage > 0, hp.isFinite, hp > 0 else { return .intact }
        hp -= damage
        if hp <= 0 { return .destroyed }
        if !showedCrack, hp <= material.hp / 2 {
            showedCrack = true
            return .cracked
        }
        return .intact
    }

    /// Jagged white fractures across the face — the "one more hit" warning.
    func showCrackOverlay() {
        let path = CGMutablePath()
        let w = size.width / 2, h = size.height / 2
        path.move(to: CGPoint(x: -w * 0.6, y: h))
        path.addLine(to: CGPoint(x: -w * 0.2, y: h * 0.2))
        path.addLine(to: CGPoint(x: -w * 0.5, y: -h * 0.4))
        path.move(to: CGPoint(x: w * 0.7, y: h * 0.6))
        path.addLine(to: CGPoint(x: w * 0.2, y: -h * 0.1))
        path.addLine(to: CGPoint(x: w * 0.4, y: -h))
        let crack = SKShapeNode(path: path)
        crack.strokeColor = UIColor.white.withAlphaComponent(0.85)
        crack.lineWidth = 1.5
        crack.lineJoin = .miter
        addChild(crack)
    }
}

/// A shadow critter — tough enough to shrug a graze (device-pass ruling):
/// bruising hits cost HP and narrow the eyes; a clean hit still one-shots.
/// Kinds (M29): shield wears a crackable dome, great is the triple-size
/// boss whose face angers per chip; hopper/mist behaviors arrive with
/// their own PRs.
final class GloomNode: SKShapeNode {
    let kind: GloomKind?
    private(set) var hp: Int
    private let maxHP: Int
    private var bruised = false
    private var shellIntact: Bool
    private var shellDome: SKShapeNode?
    /// Hopper bookkeeping.
    var lastHop: TimeInterval = 0
    /// True from take-off until the hop's own ground landing, which the
    /// damage handler forgives — a hop lands at ~2.5 impulse units, over
    /// the 1.5 bruise floor, so an unforgiven dodge would cost 1 HP and
    /// two baited hops would pop the hopper for free (review finding).
    var hopping = false

    /// Hoppers dodge (M29): when a fling lands close, leap up and away —
    /// grounded only, on a cooldown, never during the arming grace (the
    /// caller guards that). The dodge must stay IN the world: a full hop
    /// across the escape sweep counts as a self-pop, turning a missed
    /// fling into a free win (review finding). The direction never
    /// reverses — leaping back over a still-rolling sprite is a suicide
    /// dive (verified on L40) — a cornered hopper just hops SHORTER,
    /// a panic jump against the wall.
    func hopIfReady(awayFrom point: CGPoint, now: TimeInterval, worldWidth: CGFloat) {
        guard kind == .hopper,
              let body = physicsBody,
              abs(body.velocity.dy) < 8,
              now - lastHop >= MoonshotTuning.hopperCooldown else { return }
        let dx = position.x - point.x
        let dy = position.y - point.y
        guard (dx * dx + dy * dy).squareRoot() <= MoonshotTuning.hopperTriggerRadius else { return }
        let direction: CGFloat = dx < 0 ? -1 : 1
        let room = direction > 0 ? max(0, worldWidth - 40 - position.x)
                                 : max(0, position.x - 40)
        let lateral = MoonshotTuning.hopperHopLateral
            * min(1, room / MoonshotTuning.hopperHopCarry)
        lastHop = now
        hopping = true
        body.velocity = CGVector(dx: direction * lateral,
                                 dy: MoonshotTuning.hopperHopVertical)
    }

    enum HitOutcome { case none, shellShattered, bruised, popped }

    /// Applies hit points, shield-aware: an intact shell eats the first
    /// real hit whole.
    func applyHits(_ hits: Int) -> HitOutcome {
        guard hits > 0 else { return .none }
        if shellIntact {
            shellIntact = false
            shellDome?.removeFromParent()
            shellDome = nil
            return .shellShattered
        }
        hp -= hits
        if hp <= 0 { return .popped }
        if kind == .great {
            showGreatAnger()
        } else if !bruised {
            bruised = true
            showBruise()
        }
        return .bruised
    }

    /// Round eyes become angry slants, plus a crack across the shadow.
    private func showBruise() {
        children.filter { $0.name == "gloom-eye" }.forEach { $0.removeFromParent() }
        for side in [-1.0, 1.0] {
            let eye = SKShapeNode(rectOf: CGSize(width: 6, height: 2), cornerRadius: 1)
            eye.fillColor = .white
            eye.strokeColor = .clear
            eye.zRotation = side * -0.45
            eye.position = CGPoint(x: side * 5.5, y: 3)
            addChild(eye)
        }
        let crack = SKShapeNode(rectOf: CGSize(width: 1.4, height: 9), cornerRadius: 0.7)
        crack.fillColor = UIColor(white: 0.45, alpha: 1)
        crack.strokeColor = .clear
        crack.zRotation = 0.5
        crack.position = CGPoint(x: -6, y: -7)
        addChild(crack)
    }

    /// The Great Gloom's face slants steeper with every chip taken.
    private func showGreatAnger() {
        children.filter { $0.name == "gloom-eye" }.forEach { $0.removeFromParent() }
        let fraction = 1 - Double(hp) / Double(maxHP)
        for side in [-1.0, 1.0] {
            let eye = SKShapeNode(rectOf: CGSize(width: 6, height: 2), cornerRadius: 1)
            eye.fillColor = .white
            eye.strokeColor = .clear
            eye.name = "gloom-eye"
            eye.zRotation = side * -(0.15 + 0.75 * fraction)
            eye.position = CGPoint(x: side * 5.5, y: 3)
            addChild(eye)
        }
    }

    init(kind: GloomKind? = nil) {
        self.kind = kind
        let hitPoints = kind == .great ? MoonshotTuning.greatGloomHP : MoonshotTuning.gloomHP
        hp = hitPoints
        maxHP = hitPoints
        shellIntact = kind == .shield
        super.init()
        let radius = MoonshotTuning.gloomRadius
        path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
        fillColor = UIColor(white: 0.12, alpha: 1)
        strokeColor = UIColor(white: 0.3, alpha: 1)
        lineWidth = 1
        name = "gloom"

        for side in [-1.0, 1.0] {
            let eye = SKShapeNode(circleOfRadius: 2.6)
            eye.fillColor = .white
            eye.strokeColor = .clear
            eye.name = "gloom-eye"
            eye.position = CGPoint(x: side * 5.5, y: 3)
            addChild(eye)
        }

        if kind == .shield {
            let dome = SKShapeNode(circleOfRadius: radius + 5)
            dome.fillColor = UIColor.white.withAlphaComponent(0.16)
            dome.strokeColor = UIColor.white.withAlphaComponent(0.55)
            dome.lineWidth = 1.5
            dome.zPosition = 1
            addChild(dome)
            shellDome = dome
        }
        if kind == .mist {
            alpha = 0.55
            // A static wisp curl (Reduce Motion-safe) sells the vapor.
            let curl = SKShapeNode()
            let curlPath = CGMutablePath()
            curlPath.addArc(center: CGPoint(x: 6, y: -8), radius: 5,
                            startAngle: .pi, endAngle: 0, clockwise: true)
            curl.path = curlPath
            curl.strokeColor = UIColor.white.withAlphaComponent(0.6)
            curl.lineWidth = 1.2
            curl.lineCap = .round
            addChild(curl)
        }
        if kind == .great {
            setScale(MoonshotTuning.greatGloomScale)
        }

        // The body radius must be spelled out: a body created after
        // setScale does NOT inherit the node's scale, so the great's
        // radius-16 body left its 48pt art half-sunk into the floor
        // (found in the W4 stability sweep — it rested at y≈17, not 48).
        let bodyRadius = kind == .great ? radius * MoonshotTuning.greatGloomScale : radius
        let body = SKPhysicsBody(circleOfRadius: bodyRadius)
        body.density = kind == .great ? MoonshotTuning.greatGloomDensity : MoonshotTuning.gloomDensity
        body.friction = MoonshotTuning.gloomFriction
        body.restitution = MoonshotTuning.gloomRestitution
        // Glooms perch, they don't roll — a ball on a 22pt column top would
        // roll off during the settle and un-author every pillar level.
        body.allowsRotation = false
        body.fieldBitMask = FieldCategory.well
        if kind == .mist {
            // Vapor (M29): sprites and rubble pass THROUGH — the mist
            // category is two-sided-intangible to them (pieces already
            // exclude it; sprites learn to below) — but the floor is solid
            // and contact tests still fire so a live power can pop it.
            // The mist bit in the contact test is for a phasing Misty,
            // whose own category becomes mist (review finding: without it
            // the one character whose power IS mist could never touch it).
            body.categoryBitMask = PhysicsCategory.mist
            body.collisionBitMask = PhysicsCategory.ground
            body.contactTestBitMask = PhysicsCategory.sprite | PhysicsCategory.piece
                | PhysicsCategory.ground | PhysicsCategory.mist
        } else {
            body.categoryBitMask = PhysicsCategory.gloom
            body.contactTestBitMask = PhysicsCategory.sprite | PhysicsCategory.piece | PhysicsCategory.ground
        }
        physicsBody = body
    }

    required init?(coder: NSCoder) { fatalError("unused") }
}

extension CharacterID {
    /// The one place a character's body color lives — faces, ability
    /// effects, and HUD chips all derive from it.
    var bodyUIColor: UIColor {
        switch self {
        case .mochi: UIColor(Theme.glow)
        case .zip: UIColor(red: 0.35, green: 0.76, blue: 0.80, alpha: 1)
        case .twinkle: UIColor(Theme.rose)
        case .nox: UIColor(red: 0.16, green: 0.14, blue: 0.30, alpha: 1)
        case .misty: UIColor(red: 0.72, green: 0.66, blue: 0.88, alpha: 1)
        }
    }
}

/// A flingable star-sprite. Faces arrive with the characters PR; abilities
/// set `abilityActive` so contacts read the right damage multiplier.
final class StarSpriteNode: SKShapeNode {
    let character: CharacterID
    var launched = false
    var abilityActive = false
    /// True while an ability keeps this sprite "flying" though motionless
    /// (Nox's well freezes him mid-air) — spent detection skips it.
    var holdsFlight = false
    /// Misty mid-phase (M22): intangible to pieces, translucent, and
    /// remembering every piece she's currently inside. Weak entries: a
    /// piece destroyed beneath her vanishes from the set on its own, so
    /// the drain check in trackFlight re-forms her even without a didEnd.
    var phasing = false
    let phasingThrough = NSHashTable<PieceNode>.weakObjects()
    /// Set on her first piece contact — the drain check must not re-form
    /// a mist that simply hasn't reached the wall yet.
    var phaseEnteredPiece = false
    /// Flight bookkeeping for spent detection (scene time).
    var launchedAt: TimeInterval?
    var slowSince: TimeInterval?

    init(character: CharacterID) {
        self.character = character
        super.init()
        let radius = character.radius
        path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
        lineWidth = 1.5
        name = "sprite"
        drawFace()
        // No physics body until launch — the seated sprite is decorative.
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    func activatePhysics() {
        let body = SKPhysicsBody(circleOfRadius: character.radius)
        body.density = character.density
        body.friction = MoonshotTuning.spriteFriction
        body.restitution = MoonshotTuning.spriteRestitution
        // Zero air drag: the trajectory hint samples an ideal parabola, and
        // the real arc must land where the dots promised.
        body.linearDamping = 0
        // A full-speed dash moves ~30pt/frame — more than zip's own diameter
        // and any column face. Without CCD he phases through thin walls.
        body.usesPreciseCollisionDetection = true
        body.fieldBitMask = FieldCategory.wind | FieldCategory.well
        // Mist-category bodies (mist glooms, a phasing Misty) pass through:
        // Misty's phase math composes on top (&= ~piece / |= piece).
        body.collisionBitMask = ~PhysicsCategory.mist
        body.categoryBitMask = PhysicsCategory.sprite
        body.contactTestBitMask = PhysicsCategory.piece | PhysicsCategory.gloom | PhysicsCategory.ground
        physicsBody = body
    }

    /// Flesh and starlight again: restore her category, piece collisions,
    /// and full opacity. Idempotent — the drain check and the phase
    /// timeout can race.
    func resolidify() {
        guard phasing else { return }
        phasing = false
        phaseEnteredPiece = false
        phasingThrough.removeAllObjects()
        alpha = 1
        physicsBody?.categoryBitMask = PhysicsCategory.sprite
        physicsBody?.collisionBitMask |= PhysicsCategory.piece
    }

    // MARK: Code-drawn faces (M3 — no image assets, characters renameable)

    private func drawFace() {
        let radius = character.radius
        switch character {
        case .mochi:
            // The starter: a round pale-gold moon — sleepy eyes and blush.
            fillColor = character.bodyUIColor
            strokeColor = UIColor.white.withAlphaComponent(0.9)
            for side in [-1.0, 1.0] {
                let eye = SKShapeNode(rectOf: CGSize(width: 6, height: 1.8), cornerRadius: 0.9)
                eye.fillColor = UIColor(white: 0.25, alpha: 1)
                eye.strokeColor = .clear
                eye.position = CGPoint(x: side * 6.5, y: 3)
                addChild(eye)
                let blush = SKShapeNode(circleOfRadius: 2.6)
                blush.fillColor = UIColor(Theme.rose).withAlphaComponent(0.6)
                blush.strokeColor = .clear
                blush.position = CGPoint(x: side * 8.5, y: -3.5)
                addChild(blush)
            }
        case .zip:
            // The comet: teal dart with swept-back tail fins.
            fillColor = character.bodyUIColor
            strokeColor = UIColor.white.withAlphaComponent(0.85)
            for side in [-1.0, 1.0] {
                let fin = CGMutablePath()
                fin.move(to: .zero)
                fin.addLine(to: CGPoint(x: -radius * 0.9, y: side * radius * 0.55))
                fin.addLine(to: CGPoint(x: -radius * 0.35, y: side * radius * 0.15))
                fin.closeSubpath()
                let node = SKShapeNode(path: fin)
                node.fillColor = fillColor.withAlphaComponent(0.8)
                node.strokeColor = .clear
                node.position = CGPoint(x: -radius * 0.55, y: 0)
                node.zPosition = -1
                addChild(node)
            }
            addDotEyes(color: .white)
        case .twinkle:
            // The twins: one warm-pink star with a seam — it splits!
            fillColor = character.bodyUIColor
            strokeColor = UIColor.white.withAlphaComponent(0.85)
            let seam = SKShapeNode(rectOf: CGSize(width: 1.2, height: radius * 1.7))
            seam.fillColor = UIColor.white.withAlphaComponent(0.65)
            seam.strokeColor = .clear
            addChild(seam)
            addDotEyes(color: UIColor(white: 0.2, alpha: 1), spread: 8.5)
        case .nox:
            // The little black hole: deep indigo with an event-horizon ring.
            fillColor = character.bodyUIColor
            strokeColor = UIColor.white.withAlphaComponent(0.9)
            let ring = SKShapeNode(circleOfRadius: radius * 0.55)
            ring.fillColor = .clear
            ring.strokeColor = UIColor.white.withAlphaComponent(0.7)
            ring.lineWidth = 1.5
            addChild(ring)
            addDotEyes(color: .white, spread: 4.5)
        case .misty:
            // The mist-star: translucent, drowsy, with a wisp curling above.
            fillColor = character.bodyUIColor.withAlphaComponent(0.7)
            strokeColor = UIColor.white.withAlphaComponent(0.75)
            let wisp = SKShapeNode()
            let curl = CGMutablePath()
            curl.move(to: CGPoint(x: -3, y: radius - 2))
            curl.addQuadCurve(to: CGPoint(x: 6, y: radius + 6),
                              control: CGPoint(x: 8, y: radius - 1))
            wisp.path = curl
            wisp.strokeColor = UIColor.white.withAlphaComponent(0.6)
            wisp.lineWidth = 1.5
            wisp.lineCap = .round
            addChild(wisp)
            addDotEyes(color: UIColor(white: 0.35, alpha: 1))
        }
    }

    private func addDotEyes(color: UIColor, spread: CGFloat = 5.5) {
        for side in [-1.0, 1.0] {
            let eye = SKShapeNode(circleOfRadius: 2.2)
            eye.fillColor = color
            eye.strokeColor = .clear
            eye.position = CGPoint(x: side * spread, y: 3.5)
            addChild(eye)
        }
    }
}

@MainActor
enum SpriteFactory {
    static func makePiece(_ piece: MoonshotLevel.Piece) -> PieceNode { PieceNode(piece: piece) }
    static func makeGloom(at point: CGPoint, kind: GloomKind? = nil) -> GloomNode {
        let gloom = GloomNode(kind: kind)
        gloom.position = point
        return gloom
    }
    static func makeStar(_ character: CharacterID) -> StarSpriteNode { StarSpriteNode(character: character) }

    // MARK: Code-drawn textures (principle 9 — no image assets, ever)

    private static var pieceTextureCache: [String: SKTexture] = [:]

    static func pieceTexture(shape: PieceShape, material: Material) -> SKTexture {
        let key = "\(shape.rawValue)-\(material.rawValue)"
        if let cached = pieceTextureCache[key] { return cached }
        let size = shape.size
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            let cornerRadius = material == .cloudfoam
                ? min(12, size.height / 2)              // puffy
                : min(6, size.height / 4)
            // The cloud body sits lower so its scallop domes fit the canvas.
            let bumpRadius = material == .cloudfoam
                ? min(rect.width / 9, rect.height / 3)
                : 0
            var bodyRect = rect
            bodyRect.origin.y += bumpRadius * 0.7
            bodyRect.size.height -= bumpRadius * 0.7
            let path = UIBezierPath(roundedRect: bodyRect,
                                    cornerRadius: min(cornerRadius, bodyRect.height / 2))
            material.fillColor.setFill()
            path.fill()
            material.strokeColor.setStroke()
            path.lineWidth = 2
            path.stroke()
            if material == .cloudfoam {
                // Three scallop bumps along the top edge sell the cloud.
                for i in 0..<3 {
                    let bump = UIBezierPath(
                        arcCenter: CGPoint(x: rect.minX + rect.width * (0.25 + 0.25 * CGFloat(i)),
                                           y: bodyRect.minY),
                        radius: bumpRadius, startAngle: .pi, endAngle: 0, clockwise: true)
                    material.fillColor.setFill()
                    bump.fill()
                    material.strokeColor.setStroke()
                    bump.lineWidth = 2
                    bump.stroke()
                }
            }
            if material == .crystal {
                // A diagonal glint sells "glass" better than any opacity tweak.
                let glint = UIBezierPath()
                glint.move(to: CGPoint(x: rect.minX + 4, y: rect.maxY - 4))
                glint.addLine(to: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.minY + 4))
                UIColor.white.withAlphaComponent(0.7).setStroke()
                glint.lineWidth = 1.5
                glint.stroke()
            }
        }
        let texture = SKTexture(image: image)
        pieceTextureCache[key] = texture
        return texture
    }

    private static var particleDot: SKTexture = {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 8, height: 8)).fill()
        }
        return SKTexture(image: image)
    }()

    /// The equipped flight trail (M6 reward cosmetics), programmatic —
    /// `targetNode` should be the scene so particles linger behind the arc.
    /// The last gloom's send-off (M28): a burst of little four-point stars.
    static func finalSparkle(at point: CGPoint, in parent: SKNode) {
        for _ in 0..<16 {
            let star = SKShapeNode(path: starPath(radius: CGFloat.random(in: 4...8)))
            star.fillColor = UIColor(Theme.glow)
            star.strokeColor = .clear
            star.position = point
            star.zPosition = 12
            parent.addChild(star)
            let angle = Double.random(in: 0..<(2 * .pi))
            let distance = Double.random(in: 40...110)
            star.run(.sequence([
                .group([
                    .move(by: CGVector(dx: Foundation.cos(angle) * distance,
                                       dy: Foundation.sin(angle) * distance), duration: 0.6),
                    .rotate(byAngle: .pi, duration: 0.6),
                    .fadeOut(withDuration: 0.6),
                ]),
                .removeFromParent(),
            ]))
        }
    }

    private static func starPath(radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let inner = radius * 0.4
        for i in 0..<8 {
            let r = i.isMultiple(of: 2) ? radius : inner
            let angle = CGFloat(i) * .pi / 4 - .pi / 2
            let point = CGPoint(x: Foundation.cos(angle) * r, y: Foundation.sin(angle) * r)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    /// Drifting streaks that make an invisible wind zone readable (M21):
    /// particles ride the force direction at a speed that crosses the zone
    /// in roughly one lifetime.
    static func makeWindStreaks(size: CGSize, forceX: Double, forceY: Double) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        let magnitude = max((forceX * forceX + forceY * forceY).squareRoot(), 0.1)
        // Zone extent along the force direction, so an updraft's streaks
        // live long enough to cross its HEIGHT; capped for near-zero winds.
        let extent = (abs(forceX) * size.width + abs(forceY) * size.height) / magnitude
        emitter.particleTexture = particleDot
        emitter.particleBirthRate = 26
        emitter.particleLifetime = CGFloat(min(extent / (magnitude * 40), 6))
        emitter.particleSpeed = CGFloat(magnitude * 40)
        emitter.emissionAngle = CGFloat(atan2(forceY, forceX))
        emitter.particleAlpha = 0.28
        emitter.particleScale = 0.4
        emitter.particleScaleRange = 0.2
        emitter.particleColor = .white
        emitter.particleColorBlendFactor = 1
        emitter.particlePositionRange = CGVector(dx: size.width, dy: size.height)
        emitter.zPosition = -5
        return emitter
    }

    static func makeTrail(_ trail: TrailID) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = particleDot
        emitter.particleBirthRate = 42
        emitter.particleLifetime = 0.7
        emitter.particleAlpha = 0.85
        emitter.particleAlphaSpeed = -1.2
        emitter.particleScale = 0.5
        emitter.particleScaleSpeed = -0.5
        emitter.particleColorBlendFactor = 1
        emitter.zPosition = 8
        switch trail {
        case .stardust:
            emitter.particleColor = UIColor(Theme.glow)
            emitter.particleSpeed = 8
        case .petals:
            emitter.particleColor = UIColor(Theme.rose)
            emitter.particleScale = 0.65
            emitter.particleRotationSpeed = 3
            emitter.particleSpeed = 20
            emitter.emissionAngleRange = .pi * 2
        case .aurora:
            emitter.particleColor = UIColor(red: 0.4, green: 0.85, blue: 0.75, alpha: 1)
            emitter.particleColorSequence = SKKeyframeSequence(
                keyframeValues: [UIColor(red: 0.4, green: 0.85, blue: 0.75, alpha: 1),
                                 UIColor(Theme.violet)],
                times: [0, 1])
            emitter.particleBirthRate = 70
            emitter.particleLifetime = 0.9
        case .nebula:
            emitter.particleColor = UIColor(red: 0.55, green: 0.45, blue: 0.95, alpha: 1)
            emitter.particleColorSequence = SKKeyframeSequence(
                keyframeValues: [UIColor(red: 0.55, green: 0.45, blue: 0.95, alpha: 1),
                                 UIColor(Theme.rose)],
                times: [0, 1])
            emitter.particleBirthRate = 55
            emitter.particleLifetime = 1.1
            emitter.particleScale = 0.75
            emitter.particleRotationSpeed = 1.5
        }
        return emitter
    }

    /// Six physicsless shards scattering and fading — destruction feedback
    /// without particle-emitter machinery. `scale` doubles the show for the
    /// Great Gloom's fall (M29): more shards, bigger, thrown further.
    static func burst(at point: CGPoint, material: Material, in parent: SKNode, scale: CGFloat = 1) {
        for _ in 0..<Int(6 * scale) {
            let shard = SKShapeNode(rectOf: CGSize(width: 5 * scale, height: 5 * scale), cornerRadius: scale)
            shard.fillColor = material.fillColor
            shard.strokeColor = .clear
            shard.position = point
            shard.zPosition = 20
            parent.addChild(shard)
            let dx = CGFloat.random(in: (-70 * scale)...(70 * scale))
            let dy = CGFloat.random(in: 20...(110 * scale))
            shard.run(.sequence([
                .group([
                    .moveBy(x: dx, y: dy, duration: 0.4),
                    .fadeOut(withDuration: 0.4),
                    .rotate(byAngle: .random(in: -3...3), duration: 0.4),
                ]),
                .removeFromParent(),
            ]))
        }
    }

    private static var skyTextureCache: [String: SKTexture] = [:]

    /// The dreamy sky, rendered once per scene size and world (M28) from
    /// the core gradient — W1 keeps the moonlit violet, W2 drifts pinker
    /// with soft cloud blobs, W3 darkens to storm indigo with faint
    /// diagonal streaks, W4 goes near-black with watching eyes. Cached —
    /// retry and next-level rebuild the scene, not the texture.
    /// Code-drawn only (principle 9).
    static func skyTexture(size: CGSize, world: Int = 1) -> SKTexture {
        let key = "\(size.width)x\(size.height)-w\(world)"
        if let cached = skyTextureCache[key] { return cached }
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let palette: [Color] = switch world {
            case 2: [Theme.violet, Theme.rose, Theme.rose, Theme.peach]
            case 3: [Color(red: 0.13, green: 0.11, blue: 0.28), Theme.indigo, Theme.violet, Theme.rose]
            case 4: [Color(red: 0.07, green: 0.06, blue: 0.16), Color(red: 0.13, green: 0.11, blue: 0.28),
                     Theme.indigo, Theme.violet]
            default: [Theme.indigo, Theme.violet, Theme.rose, Theme.peach]
            }
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: palette.map { UIColor($0).cgColor } as CFArray,
                                      locations: [0, 0.4, 0.75, 1])!
            context.cgContext.drawLinearGradient(gradient,
                                                 start: CGPoint(x: 0, y: 0),
                                                 end: CGPoint(x: 0, y: size.height),
                                                 options: [])
            if world == 2 {
                // Soft cloud blobs: concentric fading ellipses fake a blur.
                let clouds: [(x: CGFloat, y: CGFloat, w: CGFloat)] = [
                    (0.18, 0.22, 0.34), (0.55, 0.12, 0.42), (0.82, 0.30, 0.30),
                    (0.38, 0.38, 0.26), (0.70, 0.48, 0.36),
                ]
                for cloud in clouds {
                    let width = size.width * cloud.w
                    for (scale, alpha) in [(1.0, 0.05), (0.72, 0.06), (0.45, 0.07)] {
                        let w = width * scale
                        let rect = CGRect(x: size.width * cloud.x - w / 2,
                                          y: size.height * cloud.y - w * 0.16,
                                          width: w, height: w * 0.32)
                        UIColor.white.withAlphaComponent(alpha).setFill()
                        context.cgContext.fillEllipse(in: rect)
                    }
                }
            }
            if world == 3 {
                // Faint diagonal streaks: the storm's wind made visible.
                UIColor.white.withAlphaComponent(0.08).setStroke()
                context.cgContext.setLineWidth(1)
                var x: CGFloat = -size.height * 0.6
                while x < size.width {
                    context.cgContext.move(to: CGPoint(x: x, y: 0))
                    context.cgContext.addLine(to: CGPoint(x: x + size.height * 0.58, y: size.height))
                    x += size.width / 12
                }
                context.cgContext.strokePath()
            }
            if world == 4 {
                // Watching eyes: five barely-there dot pairs in the dark —
                // the deep is looking back. Alpha 0.06 keeps them subliminal.
                let eyes: [(x: CGFloat, y: CGFloat)] = [
                    (0.14, 0.16), (0.38, 0.08), (0.63, 0.20), (0.82, 0.10), (0.50, 0.34),
                ]
                UIColor.white.withAlphaComponent(0.06).setFill()
                for eye in eyes {
                    for side: CGFloat in [-1, 1] {
                        let rect = CGRect(x: size.width * eye.x + side * 7 - 3,
                                          y: size.height * eye.y - 3,
                                          width: 6, height: 6)
                        context.cgContext.fillEllipse(in: rect)
                    }
                }
            }
        }
        let texture = SKTexture(image: image)
        skyTextureCache[key] = texture
        return texture
    }
}

private extension Material {
    var fillColor: UIColor {
        switch self {
        case .crystal: UIColor(Theme.glow).withAlphaComponent(0.55)
        case .moonwood: UIColor(red: 0.72, green: 0.55, blue: 0.42, alpha: 1)
        case .meteorstone: UIColor(red: 0.36, green: 0.36, blue: 0.52, alpha: 1)
        case .cloudfoam: UIColor(red: 0.93, green: 0.94, blue: 0.98, alpha: 0.9)
        case .frame: UIColor(white: 0.25, alpha: 1)
        }
    }

    var strokeColor: UIColor {
        switch self {
        case .crystal: UIColor.white.withAlphaComponent(0.9)
        case .moonwood: UIColor(red: 0.5, green: 0.36, blue: 0.26, alpha: 1)
        case .meteorstone: UIColor(red: 0.22, green: 0.22, blue: 0.36, alpha: 1)
        case .cloudfoam: UIColor(white: 1, alpha: 0.8)
        case .frame: UIColor(white: 0.1, alpha: 1)
        }
    }
}
