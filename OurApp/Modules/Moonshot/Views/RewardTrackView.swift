import SwiftUI
import SwiftData

/// The shared couple reward track (M6): one pool, unlocks are OURS. Shows
/// the four slice-(a) milestones and lets an unlocked trail be equipped.
struct RewardTrackView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var results: [MoonshotLevelResult]
    @Query private var cosmetics: [MoonshotCosmeticSetting]

    private let partnerID = MoonshotProgressStore.devicePartnerID

    private var pool: Int { MoonshotRewards.starPool(results.map(\.snapshot)) }
    private var equippedTrail: TrailID? {
        cosmetics.first { $0.partnerID == partnerID }?.trail
    }
    private var equippedTheme: ConstellationTheme? {
        cosmetics.first { $0.partnerID == partnerID }?.theme
    }
    private var equippedSkin: SlingshotSkin? {
        cosmetics.first { $0.partnerID == partnerID }?.skin
    }

    var body: some View {
        ZStack {
            DreamyBackground()
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 6) {
                        Text("\(pool)★")
                            .font(Theme.display(44))
                            .foregroundStyle(.white)
                        Text("Every star either of us earns lights this up")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 10)

                    ForEach(Array(MoonshotRewards.track.enumerated()), id: \.offset) { _, milestone in
                        milestoneCard(threshold: milestone.threshold, grant: milestone.grant)
                    }
                }
                .padding(24)
            }
        }
        .navigationTitle(Text("Reward track"))
    }

    @ViewBuilder
    private func milestoneCard(threshold: Int, grant: RewardGrant) -> some View {
        let reached = pool >= threshold
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(reached ? Theme.glow : Color.white.opacity(0.15))
                    .frame(width: 46, height: 46)
                Text("\(threshold)★")
                    .font(Theme.display(13))
                    .foregroundStyle(reached ? Color(red: 0.35, green: 0.3, blue: 0.2) : .white.opacity(0.7))
            }

            VStack(alignment: .leading, spacing: 2) {
                grantTitle(grant)
                    .font(Theme.display(18))
                    .foregroundStyle(.white)
                if !reached {
                    Text("Locked")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer()

            if case .trail(let trail) = grant, reached {
                equipToggle(equipped: equippedTrail == trail, title: grantTitle(grant)) {
                    MoonshotProgressStore(context: modelContext)
                        .equipTrail(equippedTrail == trail ? nil : trail)
                }
            }
            if case .theme(let theme) = grant, reached {
                equipToggle(equipped: equippedTheme == theme, title: grantTitle(grant)) {
                    MoonshotProgressStore(context: modelContext)
                        .equipTheme(equippedTheme == theme ? nil : theme)
                }
            }
            if case .skin(let skin) = grant, reached {
                equipToggle(equipped: equippedSkin == skin, title: grantTitle(grant)) {
                    MoonshotProgressStore(context: modelContext)
                        .equipSkin(equippedSkin == skin ? nil : skin)
                }
            }
            if case .character(let character) = grant, reached {
                Text(character == .nox ? "🕳️" : "🌫️").font(.system(size: 24))
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 22)
        .opacity(reached ? 1 : 0.6)
    }

    /// One equip circle, shared by every cosmetic kind — trail, theme, skin
    /// each equip independently (one slot per kind, per partner, LWW).
    private func equipToggle(equipped: Bool, title: Text, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: equipped ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24))
                .foregroundStyle(equipped ? Theme.glow : .white.opacity(0.6))
        }
        .accessibilityLabel(title)
        .accessibilityValue(equipped ? Text("Equipped") : Text("Not equipped"))
    }

    private func grantTitle(_ grant: RewardGrant) -> Text {
        switch grant {
        case .trail(.stardust): Text("Stardust")
        case .trail(.petals): Text("Petals")
        case .trail(.aurora): Text("Aurora")
        case .trail(.nebula): Text("Nebula")
        case .character(let character): Text(LocalizedStringKey(character.displayNameKey))
        case .theme(.dawn): Text("Dawn veil")
        case .skin(.golden): Text("Golden slingshot")
        }
    }
}

#Preview {
    NavigationStack { RewardTrackView() }
        .modelContainer(try! Persistence.makeContainer(inMemory: true))
}
