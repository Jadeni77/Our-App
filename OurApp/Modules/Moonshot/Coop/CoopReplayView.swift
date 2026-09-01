import SpriteKit
import SwiftUI

/// Watching her turn.
///
/// Deliberately not a game view: there is nothing to tap, because there is
/// nothing to decide. It ends by handing the turn over.
struct CoopReplayView: View {
    let level: MoonshotLevel
    let snapshot: BoardSnapshot
    let clip: FlingClip
    var onFinished: () -> Void

    @State private var finished = false
    /// Built once and held. `SpriteView(scene: makeScene())` builds a **new**
    /// scene on every body evaluation, so the replay restarts from frame one
    /// each time anything on screen changes — and the same shape of mistake
    /// froze the app outright once already.
    @State private var scene: CoopReplayScene?

    var body: some View {
        ZStack {
            if let scene {
                SpriteView(scene: scene).ignoresSafeArea()
            } else {
                DreamyBackground()
            }

            VStack {
                    Text("Waiting for \(PartnerVoice.label())")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .glassCard(cornerRadius: 18)
                        .padding(.top, 18)
                    Spacer()
                    if finished {
                        Button {
                            Haptics.tap()
                            onFinished()
                        } label: {
                            Text("Your turn")
                                .font(.system(.body, design: .rounded).weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 26)
                                .padding(.vertical, 13)
                        }
                        .glassCard(cornerRadius: 22)
                        .padding(.bottom, 28)
                        .transition(.opacity)
                    }
            }
            .animation(.easeOut(duration: 0.25), value: finished)
        }
        // A clip that can't be played is not a lost turn — the board state is
        // authoritative, so the watcher goes straight to their go rather than
        // being stuck on a blank screen.
        .task {
            if scene == nil { scene = makeScene() }
            if clip.frames.isEmpty { finished = true }
        }
    }

    private func makeScene() -> CoopReplayScene {
        let scene = CoopReplayScene(level: level, snapshot: snapshot, clip: clip)
        scene.onFinished = { finished = true }
        return scene
    }
}
