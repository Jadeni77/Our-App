import SwiftUI
import SwiftData

/// The shared couple reward track (M6): one pool, unlocks are OURS. Shows
/// every milestone on the track and lets unlocked cosmetics be equipped.
struct RewardTrackView: View {
    @Environment(\.modelContext) private var modelContext
    /// Shared: unlocks ride the pooled star count, same as Home's headline.
    @Query private var results: [MoonshotLevelResult]
    @Query private var allCosmetics: [MoonshotCosmeticSetting]
    private var cosmetics: [MoonshotCosmeticSetting] { allCosmetics.mine }
    /// One couple wallet (M31), same as Home's headline balance.
    @Query private var moondust: [MoonshotMoondustEntry]

    private let partnerID = MoonshotProgressStore.devicePartnerID

    private var pool: Int { MoonshotRewards.starPool(results.map(\.snapshot)) }
    private var moondustBalance: Int { moondust.reduce(0) { $0 + $1.amount } }
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

                    // The economy, in plain words (owner amendment #2) —
                    // then what the couple is working toward right now.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How stars work")
                            .font(Theme.display(16))
                            .foregroundStyle(.white)
                        Text("Clear a level — 1★. One over par — 2★. At or under par — 3★.")
                        Text("Both partners' best runs pool together — solo and co-op.")
                        Text("Milestones unlock characters, trails, and looks.")
                        NextUnlockStrip(pool: pool)
                            .padding(.top, 2)
                    }
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .glassCard(cornerRadius: 22)

                    // Moondust in plain words too (owner: "it seems just
                    // like numbers" — a currency must say where it's spent).
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text("What moondust does")
                                .font(Theme.display(16))
                                .foregroundStyle(.white)
                            Spacer()
                            MoondustGem()
                                .fill(Theme.glow)
                                .frame(width: 12, height: 12)
                            Text("\(moondustBalance)")
                                .font(Theme.display(14))
                                .foregroundStyle(Theme.glow)
                        }
                        Text("Smashing pieces earns moondust — tougher pieces pay more. First clears add +20.")
                        Text("Spend it mid-level: tap your star's name chip to switch who flies. The first switch is free; repeats cost 25.")
                        Text("Nox is different — summoning him costs 40 every time.")
                    }
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .glassCard(cornerRadius: 22)

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
                grant.purposeText
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
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
                Text(verbatim: characterEmoji(character)).font(.system(size: 24))
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
        grant.titleText
    }

    /// The face a reached character row wears. Verbatim on purpose — emoji
    /// aren't translated, so they should never enter the String Catalog.
    private func characterEmoji(_ character: CharacterID) -> String {
        switch character {
        case .nox: "🕳️"
        case .misty: "🌫️"
        case .pogo: "🦘"
        case .mochi, .zip, .twinkle: "⭐️"   // never on the track today
        }
    }
}

#Preview {
    NavigationStack { RewardTrackView() }
        .modelContainer(try! Persistence.makeContainer(inMemory: true))
}
