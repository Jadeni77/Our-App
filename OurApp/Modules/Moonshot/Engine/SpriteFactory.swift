import SpriteKit
import SwiftUI

/// Physics collision categories — one bit each, contacts tested across all.
enum PhysicsCategory {
    static let sprite: UInt32 = 1 << 0
    static let piece: UInt32 = 1 << 1
    static let gloom: UInt32 = 1 << 2
    static let ground: UInt32 = 1 << 3
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
        body.restitution = MoonshotTuning.pieceRestitution
        body.isDynamic = piece.material != .frame
        body.categoryBitMask = PhysicsCategory.piece
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

/// A shadow critter — pop it and its stolen starlight is free.
final class GloomNode: SKShapeNode {
    override init() {
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
            eye.position = CGPoint(x: side * 5.5, y: 3)
            addChild(eye)
        }

        let body = SKPhysicsBody(circleOfRadius: radius)
        body.density = MoonshotTuning.gloomDensity
        body.friction = MoonshotTuning.gloomFriction
        body.restitution = MoonshotTuning.pieceRestitution
        // Glooms perch, they don't roll — a ball on a 22pt column top would
        // roll off during the settle and un-author every pillar level.
        body.allowsRotation = false
        body.categoryBitMask = PhysicsCategory.gloom
        body.contactTestBitMask = PhysicsCategory.sprite | PhysicsCategory.piece | PhysicsCategory.ground
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
        body.categoryBitMask = PhysicsCategory.sprite
        body.contactTestBitMask = PhysicsCategory.piece | PhysicsCategory.gloom | PhysicsCategory.ground
        physicsBody = body
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
    static func makeGloom(at point: CGPoint) -> GloomNode {
        let gloom = GloomNode()
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
            let path = UIBezierPath(roundedRect: rect, cornerRadius: min(6, size.height / 4))
            material.fillColor.setFill()
            path.fill()
            material.strokeColor.setStroke()
            path.lineWidth = 2
            path.stroke()
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
        }
        return emitter
    }

    /// Six physicsless shards scattering and fading — destruction feedback
    /// without particle-emitter machinery.
    static func burst(at point: CGPoint, material: Material, in parent: SKNode) {
        for _ in 0..<6 {
            let shard = SKShapeNode(rectOf: CGSize(width: 5, height: 5), cornerRadius: 1)
            shard.fillColor = material.fillColor
            shard.strokeColor = .clear
            shard.position = point
            shard.zPosition = 20
            parent.addChild(shard)
            let dx = CGFloat.random(in: -70...70)
            let dy = CGFloat.random(in: 20...110)
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

    /// The dreamy sky, rendered once per scene size from the core gradient
    /// (cached — retry and next-level rebuild the scene, not the texture).
    static func skyTexture(size: CGSize) -> SKTexture {
        let key = "\(size.width)x\(size.height)"
        if let cached = skyTextureCache[key] { return cached }
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let colors = [Theme.indigo, Theme.violet, Theme.rose, Theme.peach].map { UIColor($0).cgColor }
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors as CFArray,
                                      locations: [0, 0.4, 0.75, 1])!
            context.cgContext.drawLinearGradient(gradient,
                                                 start: CGPoint(x: 0, y: 0),
                                                 end: CGPoint(x: 0, y: size.height),
                                                 options: [])
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
        case .frame: UIColor(white: 0.25, alpha: 1)
        }
    }

    var strokeColor: UIColor {
        switch self {
        case .crystal: UIColor.white.withAlphaComponent(0.9)
        case .moonwood: UIColor(red: 0.5, green: 0.36, blue: 0.26, alpha: 1)
        case .meteorstone: UIColor(red: 0.22, green: 0.22, blue: 0.36, alpha: 1)
        case .frame: UIColor(white: 0.1, alpha: 1)
        }
    }
}
