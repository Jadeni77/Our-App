import SpriteKit

/// The four tap abilities (M3). Damage multipliers live in Rules
/// (`AbilityEffects`) — this file is the physics and the spectacle.
@MainActor
enum AbilityRunner {
    static func run(_ character: CharacterID, sprite: StarSpriteNode, in scene: GameScene) {
        scene.run(SoundBank.abilityAction(for: character))
        switch character {
        case .mochi: slam(sprite, in: scene)
        case .zip: dash(sprite, in: scene)
        case .twinkle: split(sprite, in: scene)
        case .nox: gravityWell(sprite, in: scene)
        case .misty: phase(sprite, in: scene)
        }
    }

    /// Phase: Misty turns to mist — through one piece, then flesh and
    /// starlight again. GameScene.didEnd re-solidifies her as she leaves the
    /// piece; the timeout covers a phase that never touches anything.
    private static func phase(_ sprite: StarSpriteNode, in scene: GameScene) {
        guard let body = sprite.physicsBody else { return }
        sprite.phasing = true
        sprite.alpha = 0.45
        // Collision off, contact tests still on — didBegin keeps firing so
        // the scene can remember which piece she's inside.
        body.collisionBitMask &= ~PhysicsCategory.piece
        flashRing(at: sprite.position, in: scene, color: CharacterID.misty.bodyUIColor)
        scene.run(.wait(forDuration: MoonshotTuning.phaseTimeout)) { [weak sprite, weak scene] in
            guard let sprite, sprite.phasing, sprite.phasingThrough == nil else { return }
            sprite.resolidify()
            if let scene {
                flashRing(at: sprite.position, in: scene, color: CharacterID.misty.bodyUIColor)
            }
        }
    }

    /// Moon Slam: kill horizontal motion, drop like the moon itself.
    private static func slam(_ sprite: StarSpriteNode, in scene: GameScene) {
        // Post-bounce slams must fall undamped (landed damping would cap the
        // drop below its own speed); the next contact re-damps.
        sprite.physicsBody?.linearDamping = 0
        sprite.physicsBody?.velocity = CGVector(dx: 0, dy: MoonshotTuning.slamVerticalVelocity)
        sprite.abilityActive = true
        flashRing(at: sprite.position, in: scene, color: .white)
    }

    /// Comet Dash: a burst of speed along the current flight line —
    /// velocity multiplication, so the boost is mass-independent.
    private static func dash(_ sprite: StarSpriteNode, in scene: GameScene) {
        guard let body = sprite.physicsBody else { return }
        let v = body.velocity
        let speed = (v.dx * v.dx + v.dy * v.dy).squareRoot()
        // A stationary sprite can't dash, but the tap was still spent —
        // flash anyway so the player sees it registered.
        guard speed > 1 else {
            flashRing(at: sprite.position, in: scene, color: CharacterID.zip.bodyUIColor)
            return
        }
        // Same reasoning as slam: a post-bounce dash shouldn't decay against
        // landed damping — the next contact restores it.
        body.linearDamping = 0
        body.velocity = CGVector(dx: v.dx * MoonshotTuning.dashSpeedMultiplier,
                                 dy: v.dy * MoonshotTuning.dashSpeedMultiplier)
        sprite.abilityActive = true
        // A short teal streak sells the burst.
        let streak = SKShapeNode(rectOf: CGSize(width: 46, height: 4), cornerRadius: 2)
        streak.fillColor = CharacterID.zip.bodyUIColor.withAlphaComponent(0.8)
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
        let originalMass = body.mass
        let position = sprite.position
        scene.removeLaunchedSprite(sprite)
        sprite.removeFromParent()
        for side in [-1.0, 1.0] {
            let twin = SpriteFactory.makeStar(.twinkle)
            // Scale pins the LOOK and the collision radius; mass is set
            // explicitly below — never left to scale side-effects (the two
            // would silently compound: review finding on this PR).
            twin.setScale(MoonshotTuning.splitTwinScale)
            twin.position = CGPoint(x: position.x,
                                    y: position.y + side * MoonshotTuning.splitSpawnOffset)
            twin.zPosition = 10
            scene.addChild(twin)
            twin.activatePhysics()
            if let twinBody = twin.physicsBody {
                twinBody.mass = originalMass * MoonshotTuning.splitMassScale
                // Twins spawn overlapping — sprite-sprite collision off, or
                // the solver's separation kick reshapes the tuned fan.
                twinBody.collisionBitMask &= ~PhysicsCategory.sprite
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
        field.categoryBitMask = FieldCategory.well
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

    static func flashRing(at point: CGPoint, in scene: SKScene, color: UIColor) {
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
