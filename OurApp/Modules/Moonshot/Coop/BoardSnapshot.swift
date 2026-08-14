import Foundation

/// The authoritative state a co-op turn starts from — and, just as importantly,
/// **the thing that defines what each body in a clip refers to.**
///
/// The tempting shortcut is to let a clip's indices mean "the nth body the scene
/// happened to build". That is an assumption about build order holding
/// identically on two phones across two app versions, and it fails silently:
/// the clip plays, every piece animates, and they are the *wrong* pieces.
///
/// So identity lives here instead. A clip's `bodyIDs` must match a snapshot's
/// ids, and `CoopBoardRules.clip(_:matches:)` refuses the pairing when they
/// don't. Nothing has to be assumed about how a scene builds itself.
struct BoardSnapshot: Codable, Equatable {
    struct Body: Codable, Equatable {
        /// Stable across turns. Assigned when the board is first built and
        /// carried in every snapshot after, so a piece is the same piece on
        /// turn one and turn nine.
        var id: String
        /// What to rebuild — piece kind, gloom kind. Opaque to this layer; the
        /// engine owns the vocabulary.
        var kind: String
        var x: Double
        var y: Double
        var angle: Double
        var alive: Bool
    }

    var levelID: UUID
    var bodies: [Body]

    var aliveBodies: [Body] { bodies.filter(\.alive) }

    /// Cleared when no gloom is left standing — the same condition the solo
    /// game wins on, read off the board rather than off the scene, so both
    /// phones reach the same verdict from the same bytes.
    var isCleared: Bool { !bodies.contains { $0.kind == "gloom" && $0.alive } }

    /// The board as a level starts, computed **from the level definition** —
    /// no scene, no sprites, no physics.
    ///
    /// Building a `GameScene` just to read starting positions froze the app on
    /// tapping Start: `buildWorld` generates a sky texture and every sprite and
    /// physics body, synchronously, on the main thread. The give-away was the
    /// background animation stopping — a stalled main thread, not a slow query.
    ///
    /// The conversion mirrors `GameScene.levelPoint`, which is a translation by
    /// the ground height. If that ever stops being a plain translation the two
    /// must move together, which is why it says so here.
    init(startOf level: MoonshotLevel) {
        self.levelID = level.id
        self.bodies =
            level.pieces.enumerated().map { index, piece in
                Body(id: "p\(index)", kind: "piece",
                     x: piece.x, y: piece.y + Double(MoonshotTuning.groundY),
                     angle: 0, alive: true)
            }
            + level.glooms.enumerated().map { index, gloom in
                Body(id: "g\(index)", kind: "gloom",
                     x: gloom.x, y: gloom.y + Double(MoonshotTuning.groundY),
                     angle: 0, alive: true)
            }
    }

    init(levelID: UUID, bodies: [Body]) {
        self.levelID = levelID
        self.bodies = bodies
    }
}

/// JSON, deliberately — unlike `FlingClip`, which is per-frame and gets a hand
/// packed binary format. A snapshot is written once per turn and is a couple of
/// kilobytes; spending a custom codec on it would buy nothing and cost a place
/// for bugs to live.
enum BoardSnapshotCodec {
    static func encode(_ snapshot: BoardSnapshot) -> Data {
        (try? JSONEncoder().encode(snapshot)) ?? Data()
    }

    static func decode(_ data: Data) -> BoardSnapshot? {
        try? JSONDecoder().decode(BoardSnapshot.self, from: data)
    }
}

enum CoopBoardRules {
    /// Whether a clip can be played against a snapshot.
    ///
    /// Order matters as well as membership: the clip's frames are positional,
    /// so `["a","b"]` against `["b","a"]` would animate each body along the
    /// other's path — every piece moving smoothly and every piece wrong.
    static func clip(_ clip: FlingClip, matches snapshot: BoardSnapshot) -> Bool {
        clip.bodyIDs == snapshot.bodies.map(\.id)
    }

    /// The state after a turn, folded from the clip's final frame.
    ///
    /// Derived rather than sent separately: a snapshot and a clip that disagreed
    /// about where a piece finished would leave the two phones playing different
    /// games, and the only way to guarantee they agree is to compute one from
    /// the other.
    static func settledState(from clip: FlingClip, startingAt snapshot: BoardSnapshot)
        -> BoardSnapshot? {
        guard self.clip(clip, matches: snapshot), let last = clip.frames.last else { return nil }
        var settled = snapshot
        for (index, body) in settled.bodies.enumerated() where index < last.poses.count {
            var updated = body
            updated.x = last.poses[index].x
            updated.y = last.poses[index].y
            updated.angle = last.poses[index].angle
            // Once gone, gone: a body cannot come back on a later turn.
            updated.alive = body.alive && last.present[index]
            settled.bodies[index] = updated
        }
        return settled
    }
}
