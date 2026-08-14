import SpriteKit

/// Plays back a fling somebody else took.
///
/// **Nothing here simulates.** Physics is off entirely: every body is placed
/// where the clip says it was, frame by frame. That is the whole point — Box2D
/// does not produce identical results across devices, so re-running her fling
/// would show you a different pile of rubble than she saw.
@MainActor
final class CoopReplayScene: SKScene {
    private let level: MoonshotLevel
    private let snapshot: BoardSnapshot
    private let clip: FlingClip
    private var bodies: [String: SKNode] = [:]
    private var startedAt: TimeInterval?
    /// Called when the replay reaches the end, so the caller can hand the turn
    /// over rather than leaving the watcher staring at settled rubble.
    var onFinished: (() -> Void)?

    init(size: CGSize, level: MoonshotLevel, snapshot: BoardSnapshot, clip: FlingClip) {
        self.level = level
        self.snapshot = snapshot
        self.clip = clip
        super.init(size: size)
        scaleMode = .aspectFill
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func didMove(to view: SKView) {
        removeAllChildren()
        bodies = [:]

        let sky = SKSpriteNode(texture: SpriteFactory.skyTexture(size: size,
                                                                world: level.worldNumber))
        sky.position = CGPoint(x: size.width / 2, y: size.height / 2)
        sky.zPosition = -100
        addChild(sky)

        let ground = SKSpriteNode(color: UIColor(red: 0.30, green: 0.26, blue: 0.42, alpha: 1),
                                  size: CGSize(width: size.width, height: MoonshotTuning.groundY))
        ground.position = CGPoint(x: size.width / 2, y: MoonshotTuning.groundY / 2)
        ground.zPosition = -10
        addChild(ground)

        // Built from the **snapshot**, so identity comes from the same place
        // the clip's indices came from. Rebuilding from the level alone would
        // resurrect bodies destroyed on earlier turns.
        for body in snapshot.bodies where body.alive {
            guard let node = makeNode(for: body) else { continue }
            node.position = CGPoint(x: body.x, y: body.y)
            node.zRotation = body.angle
            // No physics anywhere: a body that simulated would drift away from
            // the recording within a frame or two.
            node.physicsBody = nil
            addChild(node)
            bodies[body.id] = node
        }

        // The shot, which is in the clip but not on the board — it is what the
        // turn *did*, not part of what the turn was played against. Without it
        // you watched a fort collapse for no visible reason.
        for (index, id) in clip.bodyIDs.enumerated()
        where id.hasPrefix(StarSpriteNode.recordingPrefix) {
            let raw = String(id.dropFirst(StarSpriteNode.recordingPrefix.count))
            guard let character = CharacterID(rawValue: raw) else { continue }
            let node = SpriteFactory.makeStar(character)
            node.physicsBody = nil
            // Placed on its first recorded pose, so it starts in the sling
            // rather than flashing at the origin for a frame.
            if let first = clip.frames.first, index < first.poses.count {
                node.position = CGPoint(x: first.poses[index].x, y: first.poses[index].y)
                node.zRotation = first.poses[index].angle
            }
            addChild(node)
            bodies[id] = node
        }
    }

    private func makeNode(for body: BoardSnapshot.Body) -> SKNode? {
        guard let index = Int(body.id.dropFirst()) else { return nil }
        if body.id.hasPrefix("p") {
            guard index < level.pieces.count else { return nil }
            return SpriteFactory.makePiece(level.pieces[index])
        }
        guard index < level.glooms.count else { return nil }
        return SpriteFactory.makeGloom(at: .zero, kind: level.glooms[index].kind)
    }

    override func update(_ currentTime: TimeInterval) {
        let started = startedAt ?? currentTime
        startedAt = started
        let elapsed = currentTime - started

        guard let frame = FlingPlayer.sample(clip, at: elapsed) else { return }
        for (index, id) in clip.bodyIDs.enumerated() {
            guard let node = bodies[id], index < frame.poses.count else { continue }
            if frame.present[index] {
                let pose = frame.poses[index]
                node.position = CGPoint(x: pose.x, y: pose.y)
                node.zRotation = pose.angle
            } else if node.parent != nil {
                // Destroyed mid-fling: it leaves at the frame it left in hers.
                node.removeFromParent()
            }
        }

        if elapsed >= clip.duration, let finished = onFinished {
            onFinished = nil          // once, not once per frame
            finished()
        }
    }
}
