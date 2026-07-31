import SpriteKit

/// The four tap abilities (M3). Damage multipliers live in Rules
/// (`AbilityEffects`) — this file is the physics and the spectacle.
@MainActor
enum AbilityRunner {
    static func run(_ character: CharacterID, sprite: StarSpriteNode, in scene: GameScene) {
        switch character {
        case .mochi: slam(sprite, in: scene)
        case .zip: dash(sprite, in: scene)
        case .twinkle: split(sprite, in: scene)
        case .nox: gravityWell(sprite, in: scene)
        }
    }

    /// Moon Slam: kill horizontal motion, drop like the moon itself.
    private static func slam(_ sprite: StarSpriteNode, in scene: GameScene) {
        sprite.physicsBody?.velocity = CGVector(dx: 0, dy: MoonshotTuning.slamVerticalVelocity)
        sprite.abilityActive = true
        flashRing(at: sprite.position, in: scene, color: .white)
    }

    /// Comet Dash: a burst of speed along the current flight line.
    private static func dash(_ sprite: StarSpriteNode, in scene: GameScene) {
        guard let body = sprite.physicsBody else { return }
        let v = body.velocity
        let speed = (v.dx * v.dx + v.dy * v.dy).squareRoot()
        guard speed > 1 else { return }
        body.velocity = CGVector(dx: v.dx / speed * speed * MoonshotTuning.dashSpeedMultiplier,
                                 dy: v.dy / speed * speed * MoonshotTuning.dashSpeedMultiplier)
        sprite.abilityActive = true
        // A short teal streak sells the burst.
        let streak = SKShapeNode(rectOf: CGSize(width: 46, height: 4), cornerRadius: 2)
        streak.fillColor = UIColor(red: 0.35, green: 0.76, blue: 0.80, alpha: 0.8)
        streak.strokeColor = .clear
        streak.zRotation = atan2(v.dy, v.dx)
        streak.position = sprite.position
        streak.zPosition = 9
        scene.addChild(streak)
        streak.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
    }

    /// Split: one twinkle becomes two, fanning off the flight line.
    private static func split(_ sprite: StarSpriteNode, in scene: GameScene) {
        guard let body = sprite.physicsBody else { return }
        let v = body.velocity
        let position = sprite.position
        scene.removeLaunchedSprite(sprite)
        sprite.removeFromParent()
        for side in [-1.0, 1.0] {
            let twin = SpriteFactory.makeStar(.twinkle)
            twin.setScale(0.8)
            twin.position = CGPoint(x: position.x, y: position.y + side * 6)
            twin.zPosition = 10
            scene.addChild(twin)
            twin.activatePhysics()
            if let twinBody = twin.physicsBody {
                twinBody.mass *= MoonshotTuning.splitMassScale
                let angle = Double(side) * Double(MoonshotTuning.splitAngle)
                let dx = Double(v.dx), dy = Double(v.dy)
                twinBody.velocity = CGVector(dx: dx * Foundation.cos(angle) - dy * Foundation.sin(angle),
                                             dy: dx * Foundation.sin(angle) + dy * Foundation.cos(angle))
            }
            twin.launched = true
            scene.addLaunchedSprite(twin)
        }
        flashRing(at: position, in: scene, color: UIColor(Theme.rose))
    }

    /// Gravity Well: Nox freezes and hauls the world inward for a moment.
    private static func gravityWell(_ sprite: StarSpriteNode, in scene: GameScene) {
        guard let body = sprite.physicsBody else { return }
        body.isDynamic = false   // frozen, or the well would orbit itself
        sprite.holdsFlight = true

        let field = SKFieldNode.radialGravityField()
        field.strength = MoonshotTuning.wellStrength
        field.falloff = 1
        field.region = SKRegion(radius: MoonshotTuning.wellRadius)
        field.position = sprite.position
        scene.addChild(field)

        let ring = SKShapeNode(circleOfRadius: sprite.character.radius * 1.6)
        ring.strokeColor = UIColor.white.withAlphaComponent(0.8)
        ring.fillColor = .clear
        ring.lineWidth = 2
        ring.position = sprite.position
        ring.zPosition = 9
        scene.addChild(ring)
        ring.run(.repeatForever(.sequence([
            .scale(to: 0.3, duration: 0.4),
            .scale(to: 1.0, duration: 0.0),
        ])))

        scene.run(.wait(forDuration: MoonshotTuning.wellDuration)) { [weak scene, weak sprite, weak field, weak ring] in
            field?.removeFromParent()
            ring?.removeFromParent()
            guard let scene, let sprite else { return }
            sprite.holdsFlight = false
            scene.spend(sprite)
        }
    }

    private static func flashRing(at point: CGPoint, in scene: SKScene, color: UIColor) {
        let ring = SKShapeNode(circleOfRadius: 10)
        ring.strokeColor = color.withAlphaComponent(0.85)
        ring.fillColor = .clear
        ring.lineWidth = 3
        ring.position = point
        ring.zPosition = 9
        scene.addChild(ring)
        ring.run(.sequence([
            .group([.scale(to: 4, duration: 0.35), .fadeOut(withDuration: 0.35)]),
            .removeFromParent(),
        ]))
    }
}
