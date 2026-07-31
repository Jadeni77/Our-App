import SwiftUI
import SpriteKit

/// Hosts the SpriteKit scene; the HUD overlay grows on top of this as the
/// engine gains gameplay. Scene creation is deferred to appear so the level
/// decodes once, not per render.
struct MoonshotGameView: View {
    let levelIndex: Int

    @State private var scene: GameScene?

    var body: some View {
        ZStack {
            if let scene {
                SpriteView(scene: scene)
                    .ignoresSafeArea()
            } else {
                DreamyBackground()
            }
        }
        .navigationBarBackButtonHidden(false)
        .onAppear {
            guard scene == nil else { return }
            let levels = CampaignCatalog.load().levels
            guard levels.indices.contains(levelIndex) else { return }
            let level = levels[levelIndex]
            scene = GameScene(level: level, session: LevelSession(level: level))
        }
    }
}

#Preview {
    MoonshotGameView(levelIndex: 0)
}
