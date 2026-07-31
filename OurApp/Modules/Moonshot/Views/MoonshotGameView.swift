import SwiftUI
import SwiftData
import SpriteKit

/// Hosts the SpriteKit scene with the HUD on top. The view is the
/// coordinator: it builds scene + session together (retry and next-level are
/// rebuilds), watches the observable session for win/fail, and writes the
/// result record exactly once per outcome.
struct MoonshotGameView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var currentIndex: Int
    @State private var scene: GameScene?
    @State private var session: LevelSession?
    @State private var recordedOutcome = false
    @State private var newGrants: [RewardGrant] = []

    private let catalog = CampaignCatalog.bundled

    init(levelIndex: Int) {
        _currentIndex = State(initialValue: levelIndex)
    }

    var body: some View {
        ZStack {
            if let scene {
                SpriteView(scene: scene)
                    .ignoresSafeArea()
            } else {
                DreamyBackground()
            }
            hud
            outcomeOverlay
        }
        .onAppear {
            if scene == nil { buildLevel(currentIndex) }
        }
        .onChange(of: session?.phase) { _, phase in
            guard case .won(let stars) = phase, !recordedOutcome, let session else { return }
            recordedOutcome = true
            let store = MoonshotProgressStore(context: modelContext)
            let grantsBefore = MoonshotRewards.grants(pool: store.starPool)
            store.recordSolo(levelID: session.level.id,
                             cleared: true,
                             stars: stars,
                             flings: session.flingsUsed)
            let grantsAfter = MoonshotRewards.grants(pool: store.starPool)
            newGrants = grantsAfter.filter { !grantsBefore.contains($0) }
            Haptics.success()
        }
    }

    private func buildLevel(_ index: Int) {
        guard catalog.levels.indices.contains(index) else { return }
        currentIndex = index
        recordedOutcome = false
        newGrants = []
        var level = catalog.levels[index]
        #if DEBUG
        // `-moonshotQueue zip,twinkle,nox` swaps the loaded level's lineup —
        // keeps level data honest while letting screenshots exercise any cast.
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-moonshotQueue"),
           arguments.indices.contains(flag + 1) {
            let queue = arguments[flag + 1].split(separator: ",")
                .compactMap { CharacterID(rawValue: String($0)) }
            if !queue.isEmpty { level.queue = queue }
        }
        #endif
        let newSession = LevelSession(level: level)
        let newScene = GameScene(level: level,
                                 session: newSession,
                                 showsTrajectoryHint: index < MoonshotTuning.trajectoryHintLevels,
                                 trail: MoonshotProgressStore(context: modelContext).equippedTrail)
        session = newSession
        scene = newScene
        #if DEBUG
        if arguments.contains("-moonshotAutoFling") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak newScene] in
                newScene?.debugFling(pull: CGVector(dx: -63, dy: -63))
            }
            // `-moonshotAbilityDelay 0.5` taps the ability that long after release.
            if let flag = arguments.firstIndex(of: "-moonshotAbilityDelay"),
               arguments.indices.contains(flag + 1),
               let delay = Double(arguments[flag + 1]) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2 + 0.6 + delay) { [weak newScene] in
                    newScene?.debugTapAbility()
                }
            }
        }
        #endif
    }

    // MARK: HUD

    private var hud: some View {
        VStack {
            HStack(spacing: 10) {
                if let session {
                    HStack(spacing: 10) {
                        queueDots(session)
                        Text("Fling \(min(session.flingsUsed + 1, max(session.level.queue.count, 1)))")
                        Text("Par \(session.level.par)")
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .font(Theme.display(15))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassCard(cornerRadius: 18)

                    Button {
                        Haptics.tap()
                        buildLevel(currentIndex)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                    }
                    .glassCard(cornerRadius: 18)
                    .accessibilityLabel(Text("Replay"))

                    // Nox is a choice, never a requirement: once the couple
                    // pool unlocks him, any ready fling can be swapped once.
                    if session.phase == .ready,
                       session.currentCharacter != .nox,
                       !session.usedCharacterSwap,
                       MoonshotRewards.isUnlocked(.nox, pool: MoonshotProgressStore(context: modelContext).starPool) {
                        Button {
                            Haptics.tap()
                            scene?.swapSeatedCharacter(to: .nox)
                        } label: {
                            HStack(spacing: 5) {
                                Circle().fill(CharacterID.nox.chipColor)
                                    .frame(width: 10, height: 10)
                                Text("Play as \(String(localized: "Nox"))")
                            }
                            .font(Theme.display(13))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .glassCard(cornerRadius: 18)
                    }
                }
                Spacer()
            }
            .padding(.leading, 16)
            .padding(.top, 8)
            Spacer()
        }
    }

    /// One dot per sprite still in the queue, wearing its character's color
    /// (the current one is full-size and bright; the rest wait in line).
    private func queueDots(_ session: LevelSession) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(session.upcomingCharacters.enumerated()), id: \.offset) { index, character in
                Circle()
                    .fill(character.chipColor.opacity(index == 0 ? 1 : 0.5))
                    .frame(width: index == 0 ? 10 : 8, height: index == 0 ? 10 : 8)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Win / fail overlays

    @ViewBuilder
    private var outcomeOverlay: some View {
        switch session?.phase {
        case .won(let stars):
            outcomeCard {
                starRow(stars)
                if !newGrants.isEmpty {
                    VStack(spacing: 4) {
                        Text("New unlock!")
                            .font(Theme.display(15))
                            .foregroundStyle(Theme.glow)
                        ForEach(Array(newGrants.enumerated()), id: \.offset) { _, grant in
                            grantLabel(grant)
                                .font(Theme.display(20))
                                .foregroundStyle(.white)
                        }
                    }
                }
                HStack(spacing: 14) {
                    Button { buildLevel(currentIndex) } label: { Text("Replay") }
                        .buttonStyle(MoonshotOverlayButton(prominent: false))
                    if currentIndex + 1 < catalog.levels.count {
                        Button { buildLevel(currentIndex + 1) } label: { Text("Next level") }
                            .buttonStyle(MoonshotOverlayButton(prominent: true))
                    }
                }
            }
        case .failed:
            outcomeCard {
                Text("😵‍💫").font(.system(size: 40))
                Button { buildLevel(currentIndex) } label: { Text("Try again") }
                    .buttonStyle(MoonshotOverlayButton(prominent: true))
            }
        default:
            EmptyView()
        }
    }

    private func outcomeCard(@ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 18) {
            content()
        }
        .padding(28)
        .glassCard(cornerRadius: 28)
        .transition(.scale.combined(with: .opacity))
    }

    private func grantLabel(_ grant: RewardGrant) -> Text {
        switch grant {
        case .trail(.stardust): Text("Stardust")
        case .trail(.petals): Text("Petals")
        case .trail(.aurora): Text("Aurora")
        case .character: Text("Nox")
        }
    }

    private func starRow(_ stars: Int) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { i in
                Image(systemName: i < stars ? "star.fill" : "star")
                    .font(.system(size: 30))
                    .foregroundStyle(i < stars ? Color.yellow : .white.opacity(0.4))
            }
        }
        .accessibilityLabel(Text("\(stars) stars"))
    }
}

extension CharacterID {
    /// SwiftUI color for HUD chips, derived from the one Engine palette
    /// (Views-layer on purpose: Rules stays UI-free). Nox's chip lightens
    /// his near-black body color — a true-color dot vanishes on glass.
    var chipColor: Color {
        switch self {
        case .nox: Color(red: 0.45, green: 0.42, blue: 0.72)
        default: Color(bodyUIColor)
        }
    }
}

private struct MoonshotOverlayButton: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.display(16))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(prominent ? Theme.indigo : Color.white.opacity(0.2))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

#Preview {
    MoonshotGameView(levelIndex: 0)
        .modelContainer(try! Persistence.makeContainer(inMemory: true))
}
