import Foundation
import SpriteKit

/// What co-op needs from a scene, and nothing else.
///
/// Deliberately a small surface: the recorder and player are already testable
/// without SpriteKit, and this is the only place the two worlds meet. Keeping
/// it thin is what stops "does the replay look right" turning into a question
/// only a simulator can answer.
/// Holds a destroyed body's place in the roster.
///
/// It reports itself as gone in every frame, so the watching phone is told what
/// it already knows and the board's own merge — `alive && present` — keeps it
/// dead. Its pose is never used for anything.
@MainActor
private final class DestroyedBody: RecordableBody {
    let recordingID: String
    init(recordingID: String) { self.recordingID = recordingID }
    var recordedPose: BodyPose { BodyPose(x: 0, y: 0, angle: 0) }
    var isRecordingAlive: Bool { false }
}

@MainActor
enum CoopSceneBridge {
    /// Every recordable body, **in level order** — pieces then glooms, each in
    /// the order the bundled level defines them.
    ///
    /// Order is the identity (see `BoardSnapshot`), so this must not sort by
    /// anything the scene happens to know: not z-order, not position, not the
    /// order children were added.
    /// `shot` is the sprite being flung, recorded **after** the roster so the
    /// roster's indices keep meaning what they mean. Passed in rather than
    /// discovered, because at the moment recording starts the sprite is not yet
    /// marked launched — and a flag read a line too early is exactly the kind
    /// of thing that silently records nothing.
    static func bodies(in world: SKNode, level: MoonshotLevel,
                       shot: StarSpriteNode? = nil) -> [any RecordableBody] {
        var byID: [String: any RecordableBody] = [:]
        for case let piece as PieceNode in world.children { byID[piece.coopBodyID] = piece }
        for case let gloom as GloomNode in world.children { byID[gloom.coopBodyID] = gloom }
        // **The full roster, dead included.** A board always carries every
        // body the level defines, with the destroyed ones marked — so a clip
        // must too, because the two are matched position by position.
        //
        // Dropping the dead here is what froze co-op at turn one. The moment
        // anything was destroyed, the next clip's roster was shorter than its
        // board's, `CoopBoardRules.clip(_:matches:)` refused the pair,
        // `settledState` returned nil, and the turn was thrown away — silently,
        // because refusing a turn is a legitimate outcome and looks like one.
        // The match then sat at turn one with each phone waiting on the other
        // forever.
        let roster = orderedIDs(for: level).map { id -> any RecordableBody in
            byID[id] ?? DestroyedBody(recordingID: id)
        }
        return roster + (shot.map { [$0] } ?? [])
    }

    /// The full roster a level defines, alive or not. A destroyed body has no
    /// node left, so the scene alone cannot tell you what *used* to exist —
    /// which is exactly what a snapshot has to record.
    static func orderedIDs(for level: MoonshotLevel) -> [String] {
        level.pieces.indices.map { "p\($0)" } + level.glooms.indices.map { "g\($0)" }
    }

    /// Puts a board back into a freshly built scene.
    ///
    /// Without this every turn began from the pristine level: taking your go
    /// re-ran the level from the top rather than continuing from where the last
    /// fling left it. The board was being carried faithfully between the two
    /// phones and then ignored by the one place it mattered.
    ///
    /// Snapshot coordinates are world coordinates — `BoardSnapshot(startOf:)`
    /// adds the ground offset exactly as `GameScene.levelPoint` does — so poses
    /// are assigned straight across.
    static func restore(_ snapshot: BoardSnapshot, in world: SKNode, level: MoonshotLevel) {
        var byID: [String: SKNode] = [:]
        for case let piece as PieceNode in world.children { byID[piece.coopBodyID] = piece }
        for case let gloom as GloomNode in world.children { byID[gloom.coopBodyID] = gloom }

        for body in snapshot.bodies {
            guard let node = byID[body.id] else { continue }
            guard body.alive else {
                // Destroyed on an earlier turn. Removed rather than hidden, so
                // everything that counts glooms — the win condition included —
                // sees the same board the other phone does.
                node.removeFromParent()
                continue
            }
            node.position = CGPoint(x: body.x, y: body.y)
            node.zRotation = CGFloat(body.angle)
            // Placed at rest. Any momentum left over from the drop-in would
            // shift the board before the player had touched anything, and the
            // two phones would stop agreeing about where things are.
            node.physicsBody?.velocity = .zero
            node.physicsBody?.angularVelocity = 0
        }
    }

    /// The board as it stands, in level order, with destroyed bodies marked.
    static func snapshot(of world: SKNode, level: MoonshotLevel) -> BoardSnapshot {
        var byID: [String: any RecordableBody] = [:]
        for case let piece as PieceNode in world.children { byID[piece.coopBodyID] = piece }
        for case let gloom as GloomNode in world.children { byID[gloom.coopBodyID] = gloom }

        let bodies = orderedIDs(for: level).map { id -> BoardSnapshot.Body in
            let kind = id.hasPrefix("p") ? "piece" : "gloom"
            guard let body = byID[id] else {
                // Gone. Recorded rather than omitted, so the roster stays the
                // same length on every turn and a clip's indices keep meaning
                // what they meant.
                return BoardSnapshot.Body(id: id, kind: kind, x: 0, y: 0, angle: 0, alive: false)
            }
            let pose = body.recordedPose
            return BoardSnapshot.Body(id: id, kind: kind, x: pose.x, y: pose.y,
                                      angle: pose.angle, alive: body.isRecordingAlive)
        }
        return BoardSnapshot(levelID: level.id, bodies: bodies)
    }
}
