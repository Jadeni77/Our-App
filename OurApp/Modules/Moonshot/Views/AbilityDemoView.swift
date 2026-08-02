import SwiftUI
import SpriteKit

/// The loop machinery every teaching surface shares (owner amendments #3
/// and 2026-08-02): a REAL GameScene runs a scripted shot forever —
/// fling, optional ability tap, aftermath, reset. Live physics, not a
/// recording; muted (no haptics, no session recording — nothing here
/// touches progress).
private struct DemoLoopView: View {
    let demo: AbilityDemo

    @State private var scene: GameScene?
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
        .allowsHitTesting(false)
    }

    private func restart() {
        loopTask?.cancel()
        let newScene = GameScene(level: demo.level, session: LevelSession(level: demo.level))
        scene = newScene
        generation += 1
        loopTask = Task { @MainActor [weak newScene] in
            // Settle grace (0.5 s) + a beat to read the stage.
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            newScene?.demoFling(pull: CGVector(dx: demo.pull.dx, dy: demo.pull.dy))
            if let abilityDelay = demo.abilityDelay {
                // demoFling holds 0.6 s before release; tap after launch.
                try? await Task.sleep(for: .seconds(0.6 + abilityDelay))
                guard !Task.isCancelled else { return }
                newScene?.demoTapAbility()
                try? await Task.sleep(for: .seconds(3.6))
            } else {
                // A fail demo (GloomDemos) never fires a power — just let
                // the miss play out and read for a beat.
                try? await Task.sleep(for: .seconds(4.2))
            }
            guard !Task.isCancelled else { return }
            restart()
        }
    }
}

/// One character's power, demonstrated on loop — the dashboard's player
/// and (owner amendment 2026-08-02) the meet/unlock card's centerpiece.
struct AbilityDemoView: View {
    let character: CharacterID

    var body: some View {
        DemoLoopView(demo: AbilityDemos.demo(for: character))
            .id(character)   // identity change tears down and re-scripts
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(LocalizedStringKey(character.displayNameKey)))
    }
}

/// One gloom kind's most natural attack FAILING, on loop — the enemy
/// introduction card's centerpiece (owner amendment 2026-08-02).
struct GloomDemoView: View {
    let kind: GloomKind

    var body: some View {
        DemoLoopView(demo: GloomDemos.demo(for: kind))
            .id(kind)
            .accessibilityHidden(true)   // the card's caption carries the lesson
    }
}

#Preview {
    VStack {
        AbilityDemoView(character: .zip)
            .frame(width: 480, height: 220)
        GloomDemoView(kind: .helmet)
            .frame(width: 480, height: 220)
    }
}
