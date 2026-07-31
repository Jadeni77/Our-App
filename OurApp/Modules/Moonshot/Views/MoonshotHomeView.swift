import SwiftUI

/// Moonshot's front door: Campaign is live; Co-op and 1v1 show themselves
/// locked (M14 — the roadmap teases itself, one card flips live per slice).
struct MoonshotHomeView: View {
    @Environment(\.modelContext) private var modelContext
    /// Headless screenshot paths: `-moonshotLevel N` jumps into level N
    /// (1-based); `-moonshotConstellation` / `-moonshotRewards` open those
    /// screens. DEBUG-only, like the shell's launch args.
    @State private var debugLevelIndex: Int?
    @State private var debugShowConstellation = false
    @State private var debugShowRewards = false

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-moonshotLevel"),
           arguments.indices.contains(flag + 1),
           let number = Int(arguments[flag + 1]) {
            _debugLevelIndex = State(initialValue: number - 1)
        }
        _debugShowConstellation = State(initialValue: arguments.contains("-moonshotConstellation"))
        _debugShowRewards = State(initialValue: arguments.contains("-moonshotRewards"))
        #endif
    }

    @State private var musicEnabled = MoonshotAudio.shared.musicEnabled

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground()
                VStack(spacing: 20) {
                    VStack(spacing: 6) {
                        Text("Moonshot")
                            .font(Theme.display(36))
                            .foregroundStyle(.white)
                        Text("Relight our sky")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.top, 24)
                    .overlay(alignment: .trailing) {
                        Button {
                            Haptics.tap()
                            musicEnabled.toggle()
                            MoonshotAudio.shared.musicEnabled = musicEnabled
                        } label: {
                            Image(systemName: musicEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                        }
                        .glassCard(cornerRadius: 19)
                        .offset(x: 52)
                        .accessibilityLabel(Text("Music"))
                        .accessibilityValue(musicEnabled ? Text("On") : Text("Off"))
                    }

                    NavigationLink {
                        LevelSelectView()
                    } label: {
                        modeCard(emoji: "🌌", title: "Campaign", locked: false)
                    }
                    .buttonStyle(.plain)

                    modeCard(emoji: "🤝", title: "Co-op", locked: true)
                    modeCard(emoji: "⚔️", title: "1v1", locked: true)

                    Spacer()
                }
                .padding(.horizontal, 28)
            }
            .navigationDestination(item: $debugLevelIndex) { index in
                MoonshotGameView(levelIndex: index)
            }
            .navigationDestination(isPresented: $debugShowConstellation) { LevelSelectView() }
            .navigationDestination(isPresented: $debugShowRewards) { RewardTrackView() }
            .onAppear(perform: seedStarsIfAsked)
        }
    }

    /// `-moonshotSeedStars N` writes 3★ solo clears for ⌈N/3⌉ levels so
    /// screenshots can exercise reward-track states headlessly. Idempotent
    /// (recordSolo max-merges); DEBUG-only.
    private func seedStarsIfAsked() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let store = MoonshotProgressStore(context: modelContext)
        if let flag = arguments.firstIndex(of: "-moonshotSeedStars"),
           arguments.indices.contains(flag + 1),
           let target = Int(arguments[flag + 1]) {
            for level in CampaignCatalog.bundled.levels.prefix((target + 2) / 3) {
                store.recordSolo(levelID: level.id, cleared: true, stars: 3, flings: 1)
            }
        }
        if let flag = arguments.firstIndex(of: "-moonshotEquipTrail"),
           arguments.indices.contains(flag + 1),
           let trail = TrailID(rawValue: arguments[flag + 1]) {
            store.equipTrail(trail)
        }
        if let flag = arguments.firstIndex(of: "-moonshotEquipTheme"),
           arguments.indices.contains(flag + 1),
           let theme = ConstellationTheme(rawValue: arguments[flag + 1]) {
            store.equipTheme(theme)
        }
        if let flag = arguments.firstIndex(of: "-moonshotEquipSkin"),
           arguments.indices.contains(flag + 1),
           let skin = SlingshotSkin(rawValue: arguments[flag + 1]) {
            store.equipSkin(skin)
        }
        #endif
    }

    private func modeCard(emoji: String, title: LocalizedStringKey, locked: Bool) -> some View {
        HStack(spacing: 14) {
            Text(emoji).font(.system(size: 34))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.display(20))
                    .foregroundStyle(.white)
                if locked {
                    Text("Coming soon")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer()
            Image(systemName: locked ? "lock.fill" : "chevron.right")
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(18)
        .glassCard(cornerRadius: 24)
        .opacity(locked ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    MoonshotHomeView()
}
