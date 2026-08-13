import Foundation
import SpriteKit

/// What co-op needs from a scene, and nothing else.
///
/// Deliberately a small surface: the recorder and player are already testable
/// without SpriteKit, and this is the only place the two worlds meet. Keeping
/// it thin is what stops "does the replay look right" turning into a question
/// only a simulator can answer.
@MainActor
enum CoopSceneBridge {
    /// Every recordable body, **in level order** — pieces then glooms, each in
    /// the order the bundled level defines them.
    ///
    /// Order is the identity (see `BoardSnapshot`), so this must not sort by
    /// anything the scene happens to know: not z-order, not position, not the
    /// order children were added.
    static func bodies(in world: SKNode, level: MoonshotLevel) -> [any RecordableBody] {
        var byID: [String: any RecordableBody] = [:]
        for case let piece as PieceNode in world.children { byID[piece.coopBodyID] = piece }
        for case let gloom as GloomNode in world.children { byID[gloom.coopBodyID] = gloom }
        return orderedIDs(for: level).compactMap { byID[$0] }
    }

    /// The full roster a level defines, alive or not. A destroyed body has no
    /// node left, so the scene alone cannot tell you what *used* to exist —
    /// which is exactly what a snapshot has to record.
    static func orderedIDs(for level: MoonshotLevel) -> [String] {
        level.pieces.indices.map { "p\($0)" } + level.glooms.indices.map { "g\($0)" }
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
