import SpriteKit

/// The slingshot: post visuals, rubber bands, pull clamping, trajectory
/// hint, and the release vector. Owns the seated sprite while aiming; the
/// scene takes it back at launch.
final class SlingshotNode: SKNode {
    private var loadedSprite: StarSpriteNode?
    private var bands = SKShapeNode()
    private var trajectoryDots: [SKShapeNode] = []
    private let showsTrajectoryHint: Bool

    /// Scene-space point where the waiting sprite rests (the fork).
    var seatPosition: CGPoint {
        CGPoint(x: position.x, y: position.y + MoonshotTuning.slingshotHeight)
    }

    private var forkTips: (left: CGPoint, right: CGPoint) {
        (CGPoint(x: position.x - 11, y: position.y + MoonshotTuning.slingshotHeight - 8),
         CGPoint(x: position.x + 11, y: position.y + MoonshotTuning.slingshotHeight - 8))
    }

    init(showsTrajectoryHint: Bool, skin: SlingshotSkin? = nil) {
        self.showsTrajectoryHint = showsTrajectoryHint
        super.init()
        name = "slingshot"
        zPosition = 5

        let wood: UIColor = switch skin {
        case .golden: UIColor(red: 0.85, green: 0.68, blue: 0.28, alpha: 1)
        case .obsidian: UIColor(red: 0.12, green: 0.10, blue: 0.18, alpha: 1)
        case nil: UIColor(red: 0.45, green: 0.32, blue: 0.24, alpha: 1)
        }
        // Obsidian reads as black glass, not shadow: a thin glow edge (M33).
        let edge: UIColor = skin == .obsidian ? UIColor(Theme.glow) : .clear
        let trunk = SKShapeNode(rectOf: CGSize(width: 8, height: MoonshotTuning.slingshotHeight - 18), cornerRadius: 3)
        trunk.fillColor = wood
        trunk.strokeColor = edge
        trunk.lineWidth = skin == .obsidian ? 1.5 : 0
        trunk.position = CGPoint(x: 0, y: (MoonshotTuning.slingshotHeight - 18) / 2)
        addChild(trunk)
        for side in [-1.0, 1.0] {
            let arm = SKShapeNode(rectOf: CGSize(width: 6, height: 26), cornerRadius: 3)
            arm.fillColor = wood
            arm.strokeColor = edge
            arm.lineWidth = skin == .obsidian ? 1.5 : 0
            arm.zRotation = side * 0.35
            arm.position = CGPoint(x: side * 7, y: MoonshotTuning.slingshotHeight - 22)
            addChild(arm)
        }
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    // MARK: Loading

    /// The sprite stays a child of the scene (scene coordinates throughout);
    /// the slingshot just steers it while it's seated.
    func loadSprite(_ sprite: StarSpriteNode) {
        loadedSprite = sprite
        sprite.position = seatPosition
    }

    // MARK: Drag hint (M25)

    private var dragHint: SKNode?

    /// A first-timer's hand: a fingertip dot rides the pull path from the
    /// seat down-and-back along a dashed guide with an arrowhead. Under
    /// Reduce Motion the fingertip just sits at the pull end, static.
    func showDragHint(reduceMotion: Bool) {
        removeDragHint()
        let hint = SKNode()
        hint.zPosition = 8

        let seat = CGPoint(x: 0, y: MoonshotTuning.slingshotHeight)
        let pullEnd = CGPoint(x: seat.x - 46, y: seat.y - 40)

        let guide = CGMutablePath()
        guide.move(to: seat)
        guide.addQuadCurve(to: pullEnd, control: CGPoint(x: seat.x - 32, y: seat.y - 8))
        let guideNode = SKShapeNode(path: guide.copy(dashingWithPhase: 0, lengths: [4, 5]))
        guideNode.strokeColor = UIColor.white.withAlphaComponent(0.5)
        guideNode.lineWidth = 2
        hint.addChild(guideNode)

        let head = CGMutablePath()
        head.move(to: CGPoint(x: pullEnd.x + 10, y: pullEnd.y + 6))
        head.addLine(to: pullEnd)
        head.addLine(to: CGPoint(x: pullEnd.x + 8, y: pullEnd.y + 11))
        let headNode = SKShapeNode(path: head)
        headNode.strokeColor = UIColor.white.withAlphaComponent(0.7)
        headNode.lineWidth = 2
        headNode.lineCap = .round
        hint.addChild(headNode)

        let finger = SKShapeNode(circleOfRadius: 9)
        finger.fillColor = UIColor.white.withAlphaComponent(0.85)
        finger.strokeColor = .white
        finger.lineWidth = 1.5
        finger.position = seat
        hint.addChild(finger)

        if reduceMotion {
            finger.position = pullEnd
            hint.alpha = 0.8
        } else {
            let ride = SKAction.follow(guide, asOffset: false, orientToPath: false, duration: 1.1)
            ride.timingMode = .easeInEaseOut
            finger.run(.repeatForever(.sequence([
                .fadeIn(withDuration: 0.15),
                ride,
                .wait(forDuration: 0.25),
                .fadeOut(withDuration: 0.2),
                .move(to: seat, duration: 0),
            ])))
        }
        addChild(hint)
        dragHint = hint
    }

    func removeDragHint() {
        dragHint?.removeFromParent()
        dragHint = nil
    }

    // MARK: Pulling

    /// Grabbing does NOT move the sprite (device-pass ruling 2026-07-31: a
    /// stray tap near the seat teleported the band taut and fired on lift).
    /// Only real drag movement pulls; a grab just shows the bands.
    func beginPull() {
        removeDragHint()
        guard let sprite = loadedSprite else { return }
        drawBands(to: sprite.position)
    }

    func movePull(to scenePoint: CGPoint) {
        guard let sprite = loadedSprite else { return }
        let seat = seatPosition
        var dx = scenePoint.x - seat.x
        var dy = scenePoint.y - seat.y
        let distance = (dx * dx + dy * dy).squareRoot()
        if distance > MoonshotTuning.maxPullDistance {
            let scale = MoonshotTuning.maxPullDistance / distance
            dx *= scale
            dy *= scale
        }
        sprite.position = CGPoint(x: seat.x + dx, y: seat.y + dy)
        drawBands(to: sprite.position)
        updateTrajectory(from: sprite.position, velocity: launchVelocity(for: sprite.position))
    }

    /// nil = pull too short, reseat. Otherwise the launch velocity.
    func endPull() -> CGVector? {
        defer {
            bands.removeFromParent()
            bands = SKShapeNode()
            clearTrajectory()
        }
        guard let sprite = loadedSprite else { return nil }
        let seat = seatPosition
        let dx = sprite.position.x - seat.x
        let dy = sprite.position.y - seat.y
        guard (dx * dx + dy * dy).squareRoot() >= MoonshotTuning.minPullDistance else {
            sprite.position = seat
            return nil
        }
        loadedSprite = nil
        return launchVelocity(for: sprite.position)
    }

    private func launchVelocity(for pullPoint: CGPoint) -> CGVector {
        let seat = seatPosition
        return CGVector(dx: (seat.x - pullPoint.x) * MoonshotTuning.launchVelocityPerPoint,
                        dy: (seat.y - pullPoint.y) * MoonshotTuning.launchVelocityPerPoint)
    }

    private func drawBands(to point: CGPoint) {
        bands.removeFromParent()
        guard let parent else { return }
        let path = CGMutablePath()
        let tips = forkTips
        path.move(to: convert(tips.left, from: parent))
        path.addLine(to: convert(point, from: parent))
        path.addLine(to: convert(tips.right, from: parent))
        bands = SKShapeNode(path: path)
        bands.strokeColor = UIColor(red: 0.35, green: 0.24, blue: 0.18, alpha: 1)
        bands.lineWidth = 3.5
        bands.lineCap = .round
        bands.zPosition = 9   // behind the sprite (10), in front of the post
        addChild(bands)
    }

    // MARK: Trajectory hint

    /// Sampled parabola: p(t) = p₀ + v·t + ½g·t². SpriteKit gravity is in
    /// m/s² with 1 m = 150 pt, so the point-space acceleration is g × 150 —
    /// easy to get wrong and the dots land nowhere near the real arc. The
    /// gravity knob is shared with the scene via MoonshotTuning, and launched
    /// sprites fly with zero linearDamping, so the ideal parabola IS the arc.
    /// Wind zones (M21) are DELIBERATELY ignored: reading the wind and
    /// correcting against the promise is World 3's skill.
    private func updateTrajectory(from origin: CGPoint, velocity: CGVector) {
        clearTrajectory()
        guard showsTrajectoryHint, let parent else { return }
        let gravity = Double(MoonshotTuning.gravityMetersPerSecond) * 150.0
        for i in 1...MoonshotTuning.trajectoryDots {
            let t = Double(i) * MoonshotTuning.trajectorySampleStep
            let x = Double(origin.x) + Double(velocity.dx) * t
            let y = Double(origin.y) + Double(velocity.dy) * t + 0.5 * gravity * t * t
            guard y > Double(MoonshotTuning.groundY) else { break }
            let dot = SKShapeNode(circleOfRadius: 3)
            dot.fillColor = UIColor.white.withAlphaComponent(0.55 - Double(i) * 0.05)
            dot.strokeColor = .clear
            dot.position = CGPoint(x: x, y: y)
            dot.zPosition = 4
            parent.addChild(dot)
            trajectoryDots.append(dot)
        }
    }

    private func clearTrajectory() {
        trajectoryDots.forEach { $0.removeFromParent() }
        trajectoryDots.removeAll()
    }
}
