import SpriteKit

/// Everything the Engine tells the outside world (HUD, audio, haptics all
/// hang off this — the scene never imports SwiftUI).
enum GameEvent: Equatable {
    case flung
    case impact(Material)
    case pieceDestroyed(Material)
    case gloomPopped
    case levelWon(stars: Int)
    case levelFailed
}

/// The Moonshot world: builds a `MoonshotLevel` into physics nodes and
/// drives the `LevelSession` state machine from physics reality. Static
/// camera (M16) — levels are authored to fit the 840×390 design canvas.
final class GameScene: SKScene {
    private let level: MoonshotLevel
    private let showsTrajectoryHint: Bool
    /// The equipped flight-trail cosmetic, if any (M6 reward).
    private let trail: TrailID?
    private let slingshotSkin: SlingshotSkin?
    let session: LevelSession
    var onEvent: ((GameEvent) -> Void)?

    private var worldNode = SKNode()
    private var slingshot: SlingshotNode!
    /// False during the post-build settle grace — see buildWorld.
    private var worldArmed = false

    /// SFX play here (scene-local for latency); the closure is the outside
    /// world's channel (haptics now, spectating later).
    private func emit(_ event: GameEvent) {
        if let action = SoundBank.action(for: event) { run(action) }
        onEvent?(event)
    }
    /// All launched, still-live sprites (Split will add siblings in PR 3).
    private(set) var activeSprites: [StarSpriteNode] = []

    init(level: MoonshotLevel, session: LevelSession,
         showsTrajectoryHint: Bool = false, trail: TrailID? = nil,
         slingshotSkin: SlingshotSkin? = nil) {
        self.level = level
        self.session = session
        self.showsTrajectoryHint = showsTrajectoryHint
        self.trail = trail
        self.slingshotSkin = slingshotSkin
        super.init(size: MoonshotTuning.sceneSize)
        scaleMode = .aspectFit
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override func didMove(to view: SKView) {
        backgroundColor = .black
        physicsWorld.contactDelegate = self
        // Explicit, from tuning: the trajectory hint samples the same knob.
        physicsWorld.gravity = CGVector(dx: 0, dy: MoonshotTuning.gravityMetersPerSecond)
        buildWorld()
        SoundBank.prewarm()   // playSoundFileNamed loads at construction — never mid-flight
    }

    // MARK: World construction

    /// Level coordinates are y-up-from-ground-top; scene ground top sits at
    /// `groundY`, so every authored position shifts up by that amount.
    private func levelPoint(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: x, y: y + Double(MoonshotTuning.groundY))
    }

    private func buildWorld() {
        removeAllChildren()
        worldNode = SKNode()

        let sky = SKSpriteNode(texture: SpriteFactory.skyTexture(size: size, world: level.worldNumber))
        sky.position = CGPoint(x: size.width / 2, y: size.height / 2)
        sky.zPosition = -100
        addChild(sky)

        let ground = SKSpriteNode(color: UIColor(red: 0.30, green: 0.26, blue: 0.42, alpha: 1),
                                  size: CGSize(width: size.width, height: MoonshotTuning.groundY))
        ground.position = CGPoint(x: size.width / 2, y: MoonshotTuning.groundY / 2)
        ground.zPosition = -10
        addChild(ground)

        // Floor only — NO side walls (they made overshooting flings bounce
        // back like a pinball). The floor overhangs both visible edges so
        // anything shoved out of view still comes to rest and settles.
        let bounds = SKNode()
        let floorY = MoonshotTuning.groundY
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -MoonshotTuning.floorOverhang, y: floorY))
        path.addLine(to: CGPoint(x: size.width + MoonshotTuning.floorOverhang, y: floorY))
        let body = SKPhysicsBody(edgeChainFrom: path)
        body.friction = MoonshotTuning.groundFriction
        body.restitution = 0
        body.categoryBitMask = PhysicsCategory.ground
        bounds.physicsBody = body
        addChild(bounds)

        addChild(worldNode)
        for piece in level.pieces {
            let node = SpriteFactory.makePiece(piece)
            node.position = levelPoint(piece.x, piece.y)
            worldNode.addChild(node)
        }
        for gloom in level.glooms {
            worldNode.addChild(SpriteFactory.makeGloom(at: levelPoint(gloom.x, gloom.y),
                                                       kind: gloom.kind))
        }

        var windZones = level.wind ?? []
        #if DEBUG
        if let injected = Self.debugWindZone { windZones.append(injected) }
        #endif
        for zone in windZones { addWindZone(zone) }

        slingshot = SlingshotNode(showsTrajectoryHint: showsTrajectoryHint, skin: slingshotSkin)
        slingshot.position = CGPoint(x: MoonshotTuning.slingshotX, y: MoonshotTuning.groundY)
        addChild(slingshot)
        if pendingDragHint == true {
            pendingDragHint = nil
            slingshot.showDragHint(reduceMotion: pendingDragHintReduceMotion)
        }
        activeSprites.removeAll()
        seatNextSprite()

        // The arming grace: SpriteKit's first steps resolve the authored
        // stack's tiny interpenetrations with enormous contact impulses —
        // with contacts live, the fort demolishes ITSELF at build time
        // (found the hard way: worldNode emptied within 0.3 s of building).
        // Until the world is armed, contacts deal no damage and pop nothing;
        // input stays locked on the same clock.
        worldArmed = false
        isUserInteractionEnabled = false
        run(.wait(forDuration: MoonshotTuning.settlePauseAfterBuild)) { [weak self] in
            self?.worldArmed = true
            self?.isUserInteractionEnabled = true
        }
    }

    /// A constant-force field over the zone rect plus its drifting streaks.
    /// M21: the field's category is `wind`, which only sprite bodies carry in
    /// their fieldBitMask — forts and glooms never feel it.
    private func addWindZone(_ zone: WindZone) {
        let center = levelPoint(zone.x + zone.width / 2, zone.y + zone.height / 2)
        let field = SKFieldNode.linearGravityField(
            withVector: vector_float3(Float(zone.forceX), Float(zone.forceY), 0))
        field.categoryBitMask = FieldCategory.wind
        field.region = SKRegion(path: CGPath(
            rect: CGRect(x: -zone.width / 2, y: -zone.height / 2,
                         width: zone.width, height: zone.height),
            transform: nil))
        field.position = center
        worldNode.addChild(field)

        let streaks = SpriteFactory.makeWindStreaks(
            size: CGSize(width: zone.width, height: zone.height),
            forceX: zone.forceX, forceY: zone.forceY)
        streaks.position = center
        worldNode.addChild(streaks)
    }

    #if DEBUG
    /// `-moonshotWindZone x,y,w,h,fx,fy` injects a zone into whatever level
    /// loads — wind can be verified headlessly without shipping a scratch
    /// level (the world contract test insists on 12 levels per world).
    private static var debugWindZone: WindZone? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-moonshotWindZone"),
              arguments.indices.contains(flag + 1) else { return nil }
        let parts = arguments[flag + 1].split(separator: ",").compactMap(Double.init)
        guard parts.count == 6 else { return nil }
        return WindZone(x: parts[0], y: parts[1], width: parts[2], height: parts[3],
                        forceX: parts[4], forceY: parts[5])
    }
    #endif

    // MARK: Coach hooks (M25)

    /// Fired once, on the first real pull — the coach layer marks the drag
    /// moment seen and never shows the hint again.
    var onDragHintDismissed: (() -> Void)?
    /// The view configures the scene BEFORE presentation, but the slingshot
    /// only exists after buildWorld — park the request until then.
    private var pendingDragHint: Bool?
    private var pendingDragHintReduceMotion = false

    func showDragHint(reduceMotion: Bool) {
        // Always remembered — a cancelled grab re-shows with the same style.
        pendingDragHintReduceMotion = reduceMotion
        if slingshot != nil {
            slingshot.showDragHint(reduceMotion: reduceMotion)
        } else {
            pendingDragHint = true
        }
    }

    private(set) var seatedSprite: StarSpriteNode?

    private func seatNextSprite() {
        // A HUD tap can land before didMove builds the world (scene created,
        // SpriteView not yet presented) — nothing to seat into yet.
        guard slingshot != nil else { return }
        seatedSprite?.removeFromParent()
        seatedSprite = nil
        guard let character = session.currentCharacter else { return }
        let sprite = SpriteFactory.makeStar(character)
        sprite.zPosition = 10
        addChild(sprite)
        slingshot.loadSprite(sprite)
        seatedSprite = sprite
    }

    // MARK: Input

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }

    /// The one touch that owns the current aim — a resting palm or second
    /// finger lifting elsewhere must never release the shot.
    private weak var aimingTouch: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        switch session.phase {
        case .ready:
            // Set is unordered: with a palm and the thumb landing together,
            // pick the touch that's actually grabbing, or the grab won't take.
            guard let touch = touches.first(where: {
                distance($0.location(in: self), slingshot.seatPosition) <= MoonshotTuning.grabRadius
            }) else { return }
            aimingTouch = touch
            session.beginAim()
            slingshot.beginPull()
            run(SoundBank.stretch)
        case .inFlight:
            tapAbilityNow()
        default:
            break
        }
    }

    /// One tap per flight (session enforces): route to the flying sprite.
    private func tapAbilityNow() {
        guard let character = session.tapAbility(),
              let sprite = activeSprites.first(where: { $0.character == character }) ?? activeSprites.first
        else { return }
        AbilityRunner.run(character, sprite: sprite, in: self)
    }

    /// Every flying sprite registers here — split twins included, which is
    /// how they inherit the equipped trail too.
    func addLaunchedSprite(_ sprite: StarSpriteNode) {
        activeSprites.append(sprite)
        if let trail {
            let emitter = SpriteFactory.makeTrail(trail)
            emitter.targetNode = self
            sprite.addChild(emitter)
        }
    }

    /// The HUD's character-swap path (M6: Nox is a choice): the session
    /// vetoes bad phases — only reseat when the swap actually took, or a
    /// racing tap could yank a mid-aim sprite out of the player's fingers.
    func swapSeatedCharacter(to character: CharacterID) {
        let before = session.currentCharacter
        session.swapCurrentCharacter(to: character)
        guard session.currentCharacter != before else { return }
        seatNextSprite()
    }

    func removeLaunchedSprite(_ sprite: StarSpriteNode) {
        activeSprites.removeAll { $0 === sprite }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard session.phase == .aiming,
              let touch = aimingTouch, touches.contains(touch) else { return }
        slingshot.movePull(to: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard session.phase == .aiming,
              let touch = aimingTouch, touches.contains(touch) else { return }
        aimingTouch = nil
        finishFling()
    }

    private func finishFling() {
        // seatedSprite first: endPull() is side-effectful (clears the
        // slingshot's loaded sprite on success), so it must run last.
        guard let sprite = seatedSprite, let velocity = slingshot.endPull() else {
            session.cancelAim()
            // A grab that never became a pull taught nothing (review
            // finding): put the hint back for the still-unseen learner.
            if onDragHintDismissed != nil {
                slingshot.showDragHint(reduceMotion: pendingDragHintReduceMotion)
            }
            return
        }
        sprite.activatePhysics()
        sprite.physicsBody?.velocity = velocity
        sprite.launched = true
        addLaunchedSprite(sprite)
        seatedSprite = nil
        session.fling()
        emit(.flung)
        // Only a real launch counts as "learned to pull".
        onDragHintDismissed?()
        onDragHintDismissed = nil
    }

    /// Drives the exact aim → pull → hold → release path the touch handlers
    /// use. Two callers: DEBUG verification args, and the abilities
    /// dashboard's live demo loop (owner amendment #3) — hence not DEBUG.
    func demoFling(pull: CGVector, holdFor: TimeInterval = 0.6) {
        guard slingshot != nil, worldArmed, session.phase == .ready else { return }
        aimingTouch = nil   // this aim has no owning touch; handlers must match nothing
        session.beginAim()
        let target = CGPoint(x: slingshot.seatPosition.x + pull.dx,
                             y: slingshot.seatPosition.y + pull.dy)
        slingshot.beginPull()
        slingshot.movePull(to: target)
        run(.wait(forDuration: holdFor)) { [weak self] in
            self?.finishFling()
        }
    }

    /// The ability tap by code — the same routing the in-flight touch uses.
    func demoTapAbility() {
        tapAbilityNow()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard session.phase == .aiming,
              let touch = aimingTouch, touches.contains(touch) else { return }
        aimingTouch = nil
        _ = slingshot.endPull()
        seatedSprite.map { slingshot.loadSprite($0) }
        session.cancelAim()
        if onDragHintDismissed != nil {
            slingshot.showDragHint(reduceMotion: pendingDragHintReduceMotion)
        }
    }

    // MARK: Flight & settle detection

    private var settlingSince: TimeInterval?
    private var calmSince: TimeInterval?

    override func update(_ currentTime: TimeInterval) {
        sweepEscapedGlooms()
        switch session.phase {
        case .inFlight:
            trackFlight(at: currentTime)
        case .settling:
            trackSettle(at: currentTime)
        default:
            break
        }
    }

    /// With no side walls, a gloom can be shoved clean off the map —
    /// off the map is gone (the genre's ruling): count it popped.
    private func sweepEscapedGlooms() {
        let margin = MoonshotTuning.gloomRadius * 2
        for case let gloom as GloomNode in worldNode.children where gloom.physicsBody != nil {
            if gloom.position.x < -margin || gloom.position.x > size.width + margin {
                pop(gloom)
            }
        }
    }

    private func pop(_ gloom: GloomNode) {
        gloom.physicsBody = nil
        gloom.run(.sequence([
            .group([.scale(to: 1.5, duration: 0.15), .fadeOut(withDuration: 0.15)]),
            .removeFromParent(),
        ]))
        session.gloomPopped()
        if session.gloomsRemaining == 0 {
            // The last gloom gets a send-off (M28).
            SpriteFactory.finalSparkle(at: gloom.position, in: worldNode)
        }
        emit(.gloomPopped)
    }

    private func trackFlight(at now: TimeInterval) {
        for sprite in activeSprites {
            // A drained phase — she left every piece (didEnd) or the piece
            // died beneath her (weak entries vanish without a didEnd) —
            // re-forms her here, so no path leaves a permanent ghost.
            if sprite.phasing, sprite.phaseEnteredPiece,
               sprite.phasingThrough.allObjects.isEmpty {
                sprite.resolidify()
                AbilityRunner.flashRing(at: sprite.position, in: self,
                                        color: CharacterID.misty.bodyUIColor)
            }
            if sprite.holdsFlight { continue }   // Nox's well: motionless but not spent
            if sprite.launchedAt == nil { sprite.launchedAt = now }
            let speed = sprite.physicsBody.map {
                ($0.velocity.dx * $0.velocity.dx + $0.velocity.dy * $0.velocity.dy).squareRoot()
            } ?? 0
            if speed < MoonshotTuning.spriteSpentSpeed {
                if sprite.slowSince == nil { sprite.slowSince = now }
            } else {
                sprite.slowSince = nil
            }
            let outOfWorld = sprite.position.x < -50 || sprite.position.x > size.width + 50
                || sprite.position.y < -50
            let restedOut = sprite.slowSince.map { now - $0 >= MoonshotTuning.spriteSpentDuration } ?? false
            let timedOut = sprite.launchedAt.map { now - $0 >= MoonshotTuning.flightTimeout } ?? false
            if outOfWorld || restedOut || timedOut {
                spend(sprite)
            }
        }
        if activeSprites.isEmpty {
            settlingSince = nil
            calmSince = nil
            session.flightEnded()
        }
    }

    /// Internal so AbilityRunner can retire Nox when the well collapses.
    func spend(_ sprite: StarSpriteNode) {
        activeSprites.removeAll { $0 === sprite }
        sprite.physicsBody = nil
        sprite.run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent()]))
    }

    private func trackSettle(at now: TimeInterval) {
        if settlingSince == nil { settlingSince = now }
        let everythingCalm = !worldNode.children.contains { node in
            guard let body = node.physicsBody, body.isDynamic else { return false }
            let speed = (body.velocity.dx * body.velocity.dx + body.velocity.dy * body.velocity.dy).squareRoot()
            return speed >= MoonshotTuning.settleSpeed
        }
        if everythingCalm {
            if calmSince == nil { calmSince = now }
        } else {
            calmSince = nil
        }
        let calmedDown = calmSince.map { now - $0 >= MoonshotTuning.settleDuration } ?? false
        let capExpired = settlingSince.map { now - $0 >= MoonshotTuning.settleTimeout } ?? false
        guard calmedDown || capExpired else { return }

        settlingSince = nil
        calmSince = nil
        session.settled()
        switch session.phase {
        case .won(let stars):
            emit(.levelWon(stars: stars))
        case .failed:
            emit(.levelFailed)
        case .ready:
            seatNextSprite()
        default:
            break
        }
    }
}

// MARK: - Contacts → damage

extension GameScene: SKPhysicsContactDelegate {
    func didBegin(_ contact: SKPhysicsContact) {
        let impulse = Double(contact.collisionImpulse) * MoonshotTuning.collisionImpulseScale
        let nodes = [contact.bodyA.node, contact.bodyB.node]

        guard worldArmed else {
            #if DEBUG
            // Authoring aid: a swallowed contact that could damage the most
            // fragile material means the fort is unstable as authored.
            if impulse > Material.crystal.impactThreshold {
                NSLog("Moonshot: settle grace swallowed impulse %.2f — authored fort unstable?", impulse)
            }
            #endif
            return
        }

        // Misty mid-phase (M22): a piece contact deals no damage, must not
        // land-damp her (she's passing through, not landing), and joins the
        // overlap set the drain check in trackFlight waits on. Ground and
        // gloom contacts stay normal.
        for case let sprite as StarSpriteNode in nodes.compactMap({ $0 }) where sprite.phasing {
            if let piece = nodes.compactMap({ $0 as? PieceNode }).first {
                sprite.phasingThrough.add(piece)
                sprite.phaseEnteredPiece = true
                return
            }
        }

        // Contact ends the trajectory-hint promise: restore damping so the
        // sprite settles instead of skating (device-pass fix). Runs on every
        // contact, idempotently — which also re-damps after an ability
        // zeroed it for a post-bounce boost. Above the impulse guard on
        // purpose: a zero-impulse skim must still end the free slide.
        for case let sprite as StarSpriteNode in nodes.compactMap({ $0 }) where sprite.launched {
            sprite.physicsBody?.linearDamping = MoonshotTuning.spriteLandedLinearDamping
            sprite.physicsBody?.angularDamping = MoonshotTuning.spriteLandedAngularDamping
        }
        guard impulse > 0 else { return }

        for case let piece as PieceNode in nodes.compactMap({ $0 }) where piece.parent != nil {
            let multiplier = abilityMultiplier(against: piece.material, in: nodes)
            let damage = DamageModel.damage(impulse: impulse, against: piece.material, multiplier: multiplier)
            guard damage > 0 else { continue }
            // Event semantics for PR 5's audio: a damaging hit is .impact,
            // a kill is .pieceDestroyed — never both for one contact.
            switch piece.applyDamage(damage) {
            case .intact:
                emit(.impact(piece.material))
            case .cracked:
                piece.showCrackOverlay()
                emit(.impact(piece.material))
            case .destroyed:
                SpriteFactory.burst(at: piece.position, material: piece.material, in: worldNode)
                piece.removeFromParent()
                emit(.pieceDestroyed(piece.material))
            }
        }

        let abilityContact = nodes.contains {
            ($0 as? StarSpriteNode).map { $0.abilityActive || $0.phasing } ?? false
        }
        for case let gloom as GloomNode in nodes.compactMap({ $0 }) {
            guard gloom.physicsBody != nil else { continue }
            let hits = GloomDamage.hits(forImpulse: impulse,
                                        kind: gloom.kind,
                                        abilityActive: abilityContact)
            switch gloom.applyHits(hits) {
            case .none, .bruised:
                continue                                     // face updates internally
            case .shellShattered:
                SpriteFactory.burst(at: gloom.position, material: .crystal, in: worldNode)
                emit(.impact(.crystal))
            case .popped:
                pop(gloom)
            }
        }
    }

    /// The mist leaves a piece: drop it from her overlap set. Re-forming
    /// waits for the set to DRAIN (trackFlight) — grazing a second surface
    /// mid-pass must not re-solidify her inside the first.
    func didEnd(_ contact: SKPhysicsContact) {
        let nodes = [contact.bodyA.node, contact.bodyB.node]
        for case let sprite as StarSpriteNode in nodes.compactMap({ $0 }) where sprite.phasing {
            for case let piece as PieceNode in nodes.compactMap({ $0 }) {
                sprite.phasingThrough.remove(piece)
            }
        }
    }

    /// The star sprite's ability multiplier applies only to contacts the
    /// sprite itself is part of — collapsing debris always hits at ×1.
    private func abilityMultiplier(against material: Material, in nodes: [SKNode?]) -> Double {
        for case let sprite as StarSpriteNode in nodes.compactMap({ $0 }) where sprite.launched {
            return AbilityEffects.damageMultiplier(for: sprite.character,
                                                   abilityActive: sprite.abilityActive,
                                                   against: material)
        }
        return 1
    }
}
