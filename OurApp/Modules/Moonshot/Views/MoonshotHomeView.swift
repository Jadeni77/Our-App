import SwiftUI
import SwiftData

/// Moonshot's front door, rebuilt as a progress hub (M27): Continue where
/// you left off, the three worlds at a glance, the cast with their powers
/// a tap away — and the roadmap shrunk to one quiet line.
struct MoonshotHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var results: [MoonshotLevelResult]
    private let catalog = CampaignCatalog.bundled
    private let partnerID = MoonshotProgressStore.devicePartnerID
    /// Headless screenshot paths: `-moonshotLevel N` jumps into level N
    /// (1-based); `-moonshotConstellation` / `-moonshotRewards` open those
    /// screens. DEBUG-only, like the shell's launch args.
    @State private var debugLevelIndex: Int?
    @State private var debugShowConstellation = false
    @State private var debugShowRewards = false
    @State private var debugShowAbilities = false

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
        _debugShowAbilities = State(initialValue: arguments.contains("-moonshotAbilities"))
        #endif
    }

    @State private var musicEnabled = MoonshotAudio.shared.musicEnabled

    private var pool: Int { MoonshotRewards.starPool(results.map(\.snapshot)) }

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground()
                HStack(alignment: .top, spacing: 26) {
                    VStack(spacing: 10) {
                        VStack(spacing: 4) {
                            Text("Moonshot")
                                .font(Theme.display(34))
                                .foregroundStyle(.white)
                            Text("Relight our sky")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.85))
                        }
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
                        Text("\(pool)★")
                            .font(Theme.display(30))
                            .foregroundStyle(.white)
                        Text("Every star either of us earns lights this up")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                        NextUnlockStrip(pool: pool)
                        Spacer()
                        Text("Co-op & 1v1 — on the roadmap")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: 250)

                    VStack(spacing: 14) {
                        continueHero
                        worldsRow
                        charactersRow
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 28)
                .padding(.top, 18)
                .padding(.bottom, 12)
            }
            .navigationDestination(item: $debugLevelIndex) { index in
                MoonshotGameView(levelIndex: index)
            }
            .navigationDestination(isPresented: $debugShowConstellation) { LevelSelectView() }
            .navigationDestination(isPresented: $debugShowRewards) { RewardTrackView() }
            .navigationDestination(isPresented: $debugShowAbilities) { AbilityDashboardView() }
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
        // Re-teach without wiping the store: coach moments only.
        if arguments.contains("-moonshotCoachReset") { store.resetCoach() }
        #endif
    }

    // MARK: The hub (M27)

    /// One tap back into the journey — or an invitation to replay it.
    @ViewBuilder
    private var continueHero: some View {
        let snapshots = results.map(\.snapshot)
        if let index = catalog.nextPlayableIndex(snapshots: snapshots, partnerID: partnerID) {
            NavigationLink {
                MoonshotGameView(levelIndex: index)
            } label: {
                HStack(spacing: 14) {
                    Text("🌌").font(.system(size: 32))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Continue")
                            .font(Theme.display(20))
                            .foregroundStyle(.white)
                        Text("W\(catalog.levels[index].worldNumber) · L\(index + 1)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer()
                    Image(systemName: "play.fill")
                        .foregroundStyle(Theme.glow)
                }
                .padding(16)
                .glassCard(cornerRadius: 22)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
        } else {
            NavigationLink {
                LevelSelectView()
            } label: {
                HStack(spacing: 14) {
                    Text("🌌").font(.system(size: 32))
                    Text("All clear — replay your sky")
                        .font(Theme.display(18))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(16)
                .glassCard(cornerRadius: 22)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
        }
    }

    /// Three worlds at a glance: name, banked stars, lock state.
    private var worldsRow: some View {
        let snapshots = results.map(\.snapshot)
        return HStack(spacing: 10) {
            ForEach(1...max(catalog.worldCount, 1), id: \.self) { world in
                let unlocked = catalog.isWorldUnlocked(world, snapshots: snapshots, partnerID: partnerID)
                let stars = catalog.levels(inWorld: world).reduce(0) { sum, level in
                    sum + (results.first {
                        $0.partnerID == partnerID && $0.levelID == level.id && $0.mode == .solo
                    }?.bestStars ?? 0)
                }
                NavigationLink {
                    LevelSelectView(initialWorld: world)
                } label: {
                    VStack(spacing: 4) {
                        worldName(world)
                            .font(Theme.display(12))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if unlocked {
                            Text("\(stars)★")
                                .font(.caption2)
                                .foregroundStyle(Theme.glow)
                        } else {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .glassCard(cornerRadius: 16)
                    .opacity(unlocked ? 1 : 0.6)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func worldName(_ world: Int) -> Text {
        switch world {
        case 2: Text("The Cloudfoam Skies")
        case 3: Text("The Storm Heights")
        default: Text("The Moonlit Fields")
        }
    }

    /// The cast, powers a tap away (owner amendment #3): each pick lands on
    /// that character's live demo in the dashboard.
    private var charactersRow: some View {
        HStack(spacing: 12) {
            ForEach(CharacterID.allCases, id: \.self) { character in
                let unlocked = MoonshotRewards.isUnlocked(character, pool: pool)
                NavigationLink {
                    AbilityDashboardView(initial: character)
                } label: {
                    VStack(spacing: 3) {
                        ZStack {
                            Circle()
                                .fill(unlocked ? character.chipColor : Color.white.opacity(0.15))
                                .frame(width: 40, height: 40)
                            if !unlocked {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        Text(LocalizedStringKey(character.displayNameKey))
                            .font(Theme.display(10))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityValue(unlocked ? Text("") : Text("Locked"))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 18)
    }
}

#Preview {
    MoonshotHomeView()
}
