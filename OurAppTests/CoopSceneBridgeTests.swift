import Foundation
import SpriteKit
import Testing
@testable import OurApp

/// The one place co-op meets SpriteKit, so the one place worth testing against
/// real nodes rather than a fake.
@MainActor
struct CoopSceneBridgeTests {
    private var level: MoonshotLevel {
        CampaignCatalog.bundled.levels[0]
    }

    /// A world built the way `GameScene.buildWorld` builds one, ids and all.
    private func world(for level: MoonshotLevel) -> SKNode {
        let world = SKNode()
        for (index, piece) in level.pieces.enumerated() {
            let node = SpriteFactory.makePiece(piece)
            node.coopBodyID = "p\(index)"
            world.addChild(node)
        }
        for (index, gloom) in level.glooms.enumerated() {
            let node = SpriteFactory.makeGloom(at: .zero, kind: gloom.kind)
            node.coopBodyID = "g\(index)"
            world.addChild(node)
        }
        return world
    }

    @Test func bodiesComeBackInLevelOrderNotChildOrder() {
        let level = self.level
        let scene = world(for: level)
        // Shuffling the scene's children stands in for anything that reorders
        // them — z-sorting, removal and re-add, a future refactor. Order is the
        // identity, so it must survive all of that.
        let shuffled = SKNode()
        for child in scene.children.shuffled() {
            child.removeFromParent()
            shuffled.addChild(child)
        }

        let ids = CoopSceneBridge.bodies(in: shuffled, level: level).map(\.recordingID)
        #expect(ids == CoopSceneBridge.orderedIDs(for: level))
    }

    @Test func aSnapshotKeepsItsFullRosterWhenBodiesAreDestroyed() {
        let level = self.level
        let scene = world(for: level)
        let before = CoopSceneBridge.snapshot(of: scene, level: level)
        #expect(before.bodies.count == level.pieces.count + level.glooms.count)
        // Outside the macro: `allSatisfy` is `rethrows` and `#expect` treats
        // that as throwing. Third time this has bitten in this codebase.
        let allAlive = before.bodies.allSatisfy(\.alive)
        #expect(allAlive)

        // Destroy one. The roster must stay the same length — a shorter roster
        // would silently shift every later body's index and a clip recorded
        // against it would animate the wrong pieces.
        (scene.children.first { ($0 as? PieceNode)?.coopBodyID == "p0" })?.removeFromParent()

        let after = CoopSceneBridge.snapshot(of: scene, level: level)
        #expect(after.bodies.count == before.bodies.count)
        #expect(after.bodies.first { $0.id == "p0" }?.alive == false)
        #expect(after.aliveBodies.count == before.aliveBodies.count - 1)
    }

    @Test func aClipRecordedFromTheSceneMatchesTheSceneSnapshot() {
        let level = self.level
        let scene = world(for: level)
        let bodies = CoopSceneBridge.bodies(in: scene, level: level)
        let recorder = FlingRecorder(bodies: bodies, frameRate: 30)
        recorder.sample(at: 0)
        recorder.sample(at: 1.0 / 30)

        // The whole point of the identity design: a clip recorded here plays
        // against a snapshot taken here, without either side assuming anything
        // about how the scene was built.
        let clip = recorder.finish()
        let snapshot = CoopSceneBridge.snapshot(of: scene, level: level)
        #expect(CoopBoardRules.clip(clip, matches: snapshot))
    }

    @Test func aDestroyedBodyIsRecordedAsGoneByTheRealNodes() {
        let level = self.level
        let scene = world(for: level)
        let bodies = CoopSceneBridge.bodies(in: scene, level: level)
        let recorder = FlingRecorder(bodies: bodies, frameRate: 30)
        recorder.sample(at: 0)

        // `parent == nil` is the aliveness signal, so removal is what a
        // destroyed piece looks like to the recorder.
        (bodies.first as? PieceNode)?.removeFromParent()
        recorder.sample(at: 1.0 / 30)

        let clip = recorder.finish()
        #expect(clip.frames[0].present[0] == true)
        #expect(clip.frames[1].present[0] == false)
    }
}

/// The recording hooks on the live scene, exercised without playing a level.
@MainActor
struct GameSceneCoopRecordingTests {
    private var level: MoonshotLevel { CampaignCatalog.bundled.levels[0] }

    private func scene() -> GameScene {
        let scene = GameScene(level: level, session: LevelSession(level: level))
        scene.didMove(to: SKView(frame: CGRect(origin: .zero, size: scene.size)))
        return scene
    }

    @Test func aSoloTurnRecordsNothing() {
        let game = scene()
        var recorded: FlingClip?
        game.onCoopTurnRecorded = { recorded = $0 }
        // recordsCoopTurns defaults false: a co-op concern must cost a solo
        // player nothing, not even an unused recorder allocation.
        game.update(0)
        game.update(1.0 / 60)
        #expect(recorded == nil)
    }

    @Test func theSceneExposesItsBodiesInLevelOrder() {
        let game = scene()
        guard let world = game.children.compactMap({ $0 as? SKNode })
            .first(where: { node in node.children.contains { $0 is PieceNode } })
        else {
            Issue.record("no world node with pieces")
            return
        }
        let ids = CoopSceneBridge.bodies(in: world, level: level).map(\.recordingID)
        // Every id the level declares, in the level's order — the property the
        // whole clip design rests on, checked against a scene the real
        // `buildWorld` produced rather than a hand-made one.
        #expect(ids == CoopSceneBridge.orderedIDs(for: level))
    }
}

@MainActor
struct CoopBoardRestoreTests {
    private var level: MoonshotLevel { CampaignCatalog.bundled.levels[0] }

    private func scene() -> GameScene {
        let scene = GameScene(level: level, session: LevelSession(level: level))
        scene.didMove(to: SKView(frame: CGRect(origin: .zero, size: scene.size)))
        return scene
    }

    private func worldNode(of scene: GameScene) -> SKNode? {
        scene.children.first { node in node.children.contains { $0 is PieceNode } }
    }

    @Test func restoringMovesBodiesToWhereTheLastTurnLeftThem() throws {
        let game = scene()
        let world = try #require(worldNode(of: game))
        var snapshot = CoopSceneBridge.snapshot(of: world, level: level)
        snapshot.bodies[0].x = 321
        snapshot.bodies[0].y = 210
        snapshot.bodies[0].angle = 1.25

        game.restoreCoopBoard(snapshot)

        // Turn two must start where turn one finished, or the pair spend the
        // whole match demolishing a building that keeps standing back up.
        let after = CoopSceneBridge.snapshot(of: world, level: level)
        #expect(abs(after.bodies[0].x - 321) < 0.001)
        #expect(abs(after.bodies[0].angle - 1.25) < 0.001)
    }

    @Test func restoringRemovesBodiesDestroyedOnAnEarlierTurn() throws {
        let game = scene()
        let world = try #require(worldNode(of: game))
        var snapshot = CoopSceneBridge.snapshot(of: world, level: level)
        let doomed = snapshot.bodies[0].id
        snapshot.bodies[0].alive = false

        game.restoreCoopBoard(snapshot)

        // Removed rather than hidden: a hidden body still takes part in physics
        // it has no business being in.
        let after = CoopSceneBridge.snapshot(of: world, level: level)
        #expect(after.bodies.first { $0.id == doomed }?.alive == false)
        #expect(CoopSceneBridge.bodies(in: world, level: level)
            .contains { $0.recordingID == doomed } == false)
    }

    @Test func restoredBodiesStartAtRest() throws {
        let game = scene()
        let world = try #require(worldNode(of: game))
        for case let piece as PieceNode in world.children {
            piece.physicsBody?.velocity = CGVector(dx: 500, dy: 500)
        }

        game.restoreCoopBoard(CoopSceneBridge.snapshot(of: world, level: level))

        // Carrying velocity across a turn boundary would make the board move
        // before anyone flung anything.
        let moving = world.children.contains { node in
            guard let body = node.physicsBody else { return false }
            return abs(body.velocity.dx) > 0.001 || abs(body.velocity.dy) > 0.001
        }
        #expect(moving == false)
    }
}
