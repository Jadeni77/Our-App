import SpriteKit
import SwiftUI

/// Taking your turn: the real game, recording, handing the clip to the match.
struct CoopTurnGameView: View {
    let level: MoonshotLevel
    let match: CoopMatch
    var onTurnTaken: () -> Void

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
        scene.onCoopTurnRecorded = { clip in
            // The store decides whether this counts: it re-checks the turn
            // holder, so a fling taken while her turn was already arriving is
            // refused rather than silently overwriting it.
            CoopMatchStore.takeTurn(clip: clip, by: LocalAuthor.id(),
                                    in: match, context: context)
            onTurnTaken()
        }
        return scene
    }
}
