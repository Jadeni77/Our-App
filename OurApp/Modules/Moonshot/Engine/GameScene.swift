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
    private(set) var session: LevelSession
    var onEvent: ((GameEvent) -> Void)?

    private var worldNode = SKNode()

    init(level: MoonshotLevel, session: LevelSession) {
        self.level = level
        self.session = session
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

        addChild(makeSlingshotPost())
        seatNextSprite()

        // Freeze the fort for the settle pause so authored stacks can relax
        // a point or two before anything can disturb them.
        physicsWorld.speed = 1
        isUserInteractionEnabled = false
        run(.wait(forDuration: MoonshotTuning.settlePauseAfterBuild)) { [weak self] in
            self?.isUserInteractionEnabled = true
        }
    }

    /// A simple forked post — the band and pull mechanics arrive with the
    /// slingshot task; the post gives the world its landmark now.
    private func makeSlingshotPost() -> SKNode {
        let post = SKNode()
        post.position = CGPoint(x: MoonshotTuning.slingshotX, y: MoonshotTuning.groundY)

        let trunk = SKShapeNode(rectOf: CGSize(width: 8, height: MoonshotTuning.slingshotHeight - 18), cornerRadius: 3)
        trunk.fillColor = UIColor(red: 0.45, green: 0.32, blue: 0.24, alpha: 1)
        trunk.strokeColor = .clear
        trunk.position = CGPoint(x: 0, y: (MoonshotTuning.slingshotHeight - 18) / 2)
        post.addChild(trunk)

        for side in [-1.0, 1.0] {
            let arm = SKShapeNode(rectOf: CGSize(width: 6, height: 26), cornerRadius: 3)
            arm.fillColor = trunk.fillColor
            arm.strokeColor = .clear
            arm.zRotation = side * 0.35
            arm.position = CGPoint(x: side * 7, y: MoonshotTuning.slingshotHeight - 22)
            post.addChild(arm)
        }
        post.zPosition = 5
        post.name = "slingshot-post"
        return post
    }

    private(set) var seatedSprite: StarSpriteNode?

    var seatPosition: CGPoint {
        CGPoint(x: MoonshotTuning.slingshotX,
                y: MoonshotTuning.groundY + MoonshotTuning.slingshotHeight)
    }

    private func seatNextSprite() {
        seatedSprite?.removeFromParent()
        seatedSprite = nil
        guard let character = session.currentCharacter else { return }
        let sprite = SpriteFactory.makeStar(character)
        sprite.position = seatPosition
        sprite.zPosition = 10
        addChild(sprite)
        seatedSprite = sprite
    }
}
