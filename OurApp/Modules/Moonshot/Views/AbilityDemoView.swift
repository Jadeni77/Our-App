import SwiftUI
import SpriteKit

/// A self-playing demonstration (owner amendment #3): a REAL GameScene runs
/// the character's scripted shot on a loop — fling, ability, aftermath,
/// reset. Live physics, not a recording; muted (no haptics, no session
/// recording — nothing here touches progress).
struct AbilityDemoView: View {
    let character: CharacterID

    @State private var scene: GameScene?
    @State private var session: LevelSession?
    @State private var generation = 0
    @State private var loopTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if let scene {
                SpriteView(scene: scene)
                    .id(generation)
            } else {
                DreamyBackground()
            }
        }
        .onAppear { restart() }
        .onDisappear { loopTask?.cancel() }
        .onChange(of: character) { restart() }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey(character.displayNameKey)))
    }

    private func restart() {
        loopTask?.cancel()
        let demo = AbilityDemos.demo(for: character)
        let newSession = LevelSession(level: demo.level)
        let newScene = GameScene(level: demo.level, session: newSession)
        session = newSession
        scene = newScene
        generation += 1
        loopTask = Task { @MainActor [weak newScene] in
            // Settle grace (0.5 s) + a beat to read the stage.
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            newScene?.demoFling(pull: CGVector(dx: demo.pull.dx, dy: demo.pull.dy))
            // demoFling holds 0.6 s before release; tap after launch.
            try? await Task.sleep(for: .seconds(0.6 + demo.abilityDelay))
            guard !Task.isCancelled else { return }
            newScene?.demoTapAbility()
            // Let the aftermath play, then run it again from the top.
            try? await Task.sleep(for: .seconds(3.6))
            guard !Task.isCancelled else { return }
            restart()
        }
    }
}

#Preview {
    AbilityDemoView(character: .zip)
        .frame(width: 480, height: 220)
}
