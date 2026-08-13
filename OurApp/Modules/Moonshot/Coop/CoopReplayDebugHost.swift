#if DEBUG
import SwiftUI

/// `-coopReplay` opens the spectator view on a synthetic fling.
///
/// A replay is otherwise only reachable by two people taking turns on two
/// phones, which is not something a headless screenshot can arrange — and the
/// replay path is exactly the one whose bugs are invisible to the person who
/// took the shot.
struct CoopReplayDebugHost: View {
    private let level = CampaignCatalog.bundled.levels[0]

    var body: some View {
        let snapshot = BoardSnapshot(
            levelID: level.id,
            bodies: CoopSceneBridge.orderedIDs(for: level).enumerated().map { index, id in
                BoardSnapshot.Body(id: id, kind: id.hasPrefix("p") ? "piece" : "gloom",
                                   x: 520 + Double(index % 4) * 46,
                                   y: MoonshotTuning.groundY + 24 + Double(index / 4) * 46,
                                   angle: 0, alive: true)
            })

        // A plausible fling: everything topples rightward and settles, and the
        // last two bodies are destroyed partway through so the presence path
        // gets exercised rather than just the movement.
        let frames = (0..<45).map { step -> FlingClip.Frame in
            let t = Double(step) / 44
            return FlingClip.Frame(
                poses: snapshot.bodies.enumerated().map { index, body in
                    BodyPose(x: body.x + t * Double(30 + index * 3),
                             y: body.y - t * t * Double(40 + index * 5),
                             angle: t * Double(index % 5) * 0.9)
                },
                present: snapshot.bodies.indices.map { index in
                    !(step > 25 && index >= snapshot.bodies.count - 2)
                })
        }

        return CoopReplayView(level: level, snapshot: snapshot,
                              clip: FlingClip(frameRate: 30,
                                              bodyIDs: snapshot.bodies.map(\.id),
                                              frames: frames),
                              onFinished: {})
    }
}
#endif
