import SpriteKit
import SwiftUI

/// Taking your turn: the real game, recording, handing the clip to the match.
struct CoopTurnGameView: View {
    let level: MoonshotLevel
    let match: CoopMatch
    /// Carries whether the turn was actually recorded. A refusal is a
    /// legitimate outcome — the other phone may have got there first — but it
    /// must never be indistinguishable from success.
    var onTurnTaken: (Bool) -> Void

    @Environment(\.modelContext) private var context
    @State private var scene: GameScene?

    var body: some View {
        ZStack {
            if let scene {
                SpriteView(scene: scene).ignoresSafeArea()
            } else {
                DreamyBackground()
            }
        }
        .task { if scene == nil { scene = makeScene() } }
    }

    private func makeScene() -> GameScene {
        let scene = GameScene(level: level, session: LevelSession(level: level))
        scene.recordsCoopTurns = true
        // **Where the last fling left it, not the top of the level.** The board
        // was already being carried between the phones; this is the one place
        // it was being thrown away, which is why taking your turn looked like
        // starting a new game.
        scene.coopStartingBoard = BoardSnapshotCodec.decode(match.boardState)
        scene.onCoopTurnRecorded = { clip in
            // The store decides whether this counts: it re-checks the turn
            // holder, so a fling taken while her turn was already arriving is
            // refused rather than silently overwriting it.
            let turn = CoopMatchStore.takeTurn(clip: clip, by: LocalAuthor.id(),
                                               in: match, context: context)
            onTurnTaken(turn != nil)
        }
        return scene
    }
}
