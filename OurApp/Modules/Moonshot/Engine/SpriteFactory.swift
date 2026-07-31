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
        body.friction = 0.8
        body.restitution = 0.05
        body.isDynamic = piece.material != .frame
        body.categoryBitMask = PhysicsCategory.piece
        body.contactTestBitMask = PhysicsCategory.sprite | PhysicsCategory.piece | PhysicsCategory.ground
        physicsBody = body
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    func applyDamage(_ damage: Double) -> Fate {
        guard damage > 0, hp.isFinite else { return .intact }
        hp -= damage
        if hp <= 0 { return .destroyed }
        if !showedCrack, hp <= material.hp / 2 {
            showedCrack = true
            return .cracked
        }
        return .intact
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
        body.density = 0.8
        body.friction = 0.9
        body.restitution = 0.05
        body.categoryBitMask = PhysicsCategory.gloom
        body.contactTestBitMask = PhysicsCategory.sprite | PhysicsCategory.piece | PhysicsCategory.ground
        physicsBody = body
    }

    required init?(coder: NSCoder) { fatalError("unused") }
}

/// A flingable star-sprite. Faces arrive with the characters PR; abilities
/// set `abilityActive` so contacts read the right damage multiplier.
final class StarSpriteNode: SKShapeNode {
    let character: CharacterID
    var launched = false
    var abilityActive = false

    init(character: CharacterID) {
        self.character = character
        super.init()
        let radius: CGFloat = 16
        path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
        fillColor = UIColor(Theme.glow)
        strokeColor = UIColor.white.withAlphaComponent(0.9)
        lineWidth = 1.5
        name = "sprite"
        // No physics body until launch — the seated sprite is decorative.
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    func activatePhysics() {
        let body = SKPhysicsBody(circleOfRadius: 16)
        body.density = 1.2
        body.friction = 0.6
        body.restitution = 0.2
        body.categoryBitMask = PhysicsCategory.sprite
        body.contactTestBitMask = PhysicsCategory.piece | PhysicsCategory.gloom | PhysicsCategory.ground
        physicsBody = body
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

    /// The dreamy sky, rendered once per scene size from the core gradient.
    static func skyTexture(size: CGSize) -> SKTexture {
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
        return SKTexture(image: image)
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
