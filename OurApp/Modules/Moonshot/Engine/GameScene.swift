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
    private(set) var session: LevelSession
    var onEvent: ((GameEvent) -> Void)?

    private var worldNode = SKNode()
    private var slingshot: SlingshotNode!
    /// All launched, still-live sprites (Split will add siblings in PR 3).
    private(set) var activeSprites: [StarSpriteNode] = []

    init(level: MoonshotLevel, session: LevelSession, showsTrajectoryHint: Bool = false) {
        self.level = level
        self.session = session
        self.showsTrajectoryHint = showsTrajectoryHint
        super.init(size: MoonshotTuning.sceneSize)
        scaleMode = .aspectFit
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override func didMove(to view: SKView) {
        backgroundColor = .black
        buildWorld()
    }

    /// Fresh session, fresh fort — the retry path.
    func retry() {
        session = LevelSession(level: level)
        buildWorld()
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

        let sky = SKSpriteNode(texture: SpriteFactory.skyTexture(size: size))
        sky.position = CGPoint(x: size.width / 2, y: size.height / 2)
        sky.zPosition = -100
        addChild(sky)

        let ground = SKSpriteNode(color: UIColor(red: 0.30, green: 0.26, blue: 0.42, alpha: 1),
                                  size: CGSize(width: size.width, height: MoonshotTuning.groundY))
        ground.position = CGPoint(x: size.width / 2, y: MoonshotTuning.groundY / 2)
        ground.zPosition = -10
        addChild(ground)

        // One edge loop: floor at the ground top plus side walls, top open.
        let bounds = SKNode()
        let floorY = MoonshotTuning.groundY
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: size.height * 2))
        path.addLine(to: CGPoint(x: 0, y: floorY))
        path.addLine(to: CGPoint(x: size.width, y: floorY))
        path.addLine(to: CGPoint(x: size.width, y: size.height * 2))
        let body = SKPhysicsBody(edgeChainFrom: path)
        body.friction = 0.9
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
            worldNode.addChild(SpriteFactory.makeGloom(at: levelPoint(gloom.x, gloom.y)))
        }

        slingshot = SlingshotNode(showsTrajectoryHint: showsTrajectoryHint)
        slingshot.position = CGPoint(x: MoonshotTuning.slingshotX, y: MoonshotTuning.groundY)
        addChild(slingshot)
        activeSprites.removeAll()
        seatNextSprite()

        // Freeze the fort for the settle pause so authored stacks can relax
        // a point or two before anything can disturb them.
        physicsWorld.speed = 1
        isUserInteractionEnabled = false
        run(.wait(forDuration: MoonshotTuning.settlePauseAfterBuild)) { [weak self] in
            self?.isUserInteractionEnabled = true
        }
    }

    private(set) var seatedSprite: StarSpriteNode?

    private func seatNextSprite() {
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

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        switch session.phase {
        case .ready where distance(point, slingshot.seatPosition) <= MoonshotTuning.grabRadius:
            session.beginAim()
            slingshot.beginPull(at: point)
        case .inFlight:
            break   // ability tap — arrives with the characters PR
        default:
            break
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard session.phase == .aiming, let point = touches.first?.location(in: self) else { return }
        slingshot.movePull(to: point)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard session.phase == .aiming else { return }
        finishFling()
    }

    private func finishFling() {
        guard let velocity = slingshot.endPull(), let sprite = seatedSprite else {
            session.cancelAim()
            return
        }
        sprite.activatePhysics()
        sprite.physicsBody?.velocity = velocity
        sprite.launched = true
        activeSprites.append(sprite)
        seatedSprite = nil
        session.fling()
        onEvent?(.flung)
    }

    #if DEBUG
    /// Headless verification: drives the exact aim → pull → hold → release
    /// path the touch handlers use, so screenshots can watch a real fling.
    func debugFling(pull: CGVector, holdFor: TimeInterval = 0.6) {
        guard session.phase == .ready else { return }
        session.beginAim()
        let target = CGPoint(x: slingshot.seatPosition.x + pull.dx,
                             y: slingshot.seatPosition.y + pull.dy)
        slingshot.beginPull(at: target)
        slingshot.movePull(to: target)
        run(.wait(forDuration: holdFor)) { [weak self] in
            self?.finishFling()
        }
    }
    #endif

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard session.phase == .aiming else { return }
        _ = slingshot.endPull()
        seatedSprite.map { slingshot.loadSprite($0) }
        session.cancelAim()
    }
}
