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
                Button {
                    Haptics.tap()
                    let store = MoonshotProgressStore(context: modelContext)
                    store.equipTrail(equippedTrail == trail ? nil : trail)
                } label: {
                    Image(systemName: equippedTrail == trail ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundStyle(equippedTrail == trail ? Theme.glow : .white.opacity(0.6))
                }
                .accessibilityLabel(grantTitle(grant))
                .accessibilityValue(equippedTrail == trail ? Text("Equipped") : Text("Not equipped"))
            }
            if case .character = grant, reached {
                Text("🕳️").font(.system(size: 24))
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 22)
        .opacity(reached ? 1 : 0.6)
    }

    private func grantTitle(_ grant: RewardGrant) -> Text {
        switch grant {
        case .trail(.stardust): Text("Stardust")
        case .trail(.petals): Text("Petals")
        case .trail(.aurora): Text("Aurora")
        case .character: Text("Nox")
        }
    }
}

#Preview {
    NavigationStack { RewardTrackView() }
        .modelContainer(try! Persistence.makeContainer(inMemory: true))
}
