import SwiftUI
import SwiftData

/// The abilities dashboard (owner amendment #3): every character, every
/// power, DEMONSTRATED — a live physics loop per star, not a description.
/// Locked characters demo too; watching the well work is the best
/// advertisement for earning 24★.
struct AbilityDashboardView: View {
    /// Personal: an ability is unlocked by *your* play, not by hers.
    @Query private var allResults: [MoonshotLevelResult]
    private var results: [MoonshotLevelResult] { allResults.mine }
    @State private var selected: CharacterID

    init(initial: CharacterID = .mochi) {
        _selected = State(initialValue: initial)
    }

    private var pool: Int { MoonshotRewards.starPool(results.map(\.snapshot)) }

    var body: some View {
        ZStack {
            DreamyBackground()
            HStack(spacing: 20) {
                VStack(spacing: 12) {
                    ForEach(CharacterID.allCases, id: \.self) { character in
                        characterPick(character)
                    }
                }
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Text(LocalizedStringKey(selected.displayNameKey))
                            .font(Theme.display(24))
                            .foregroundStyle(.white)
                        if !isUnlocked(selected), let threshold = threshold(selected) {
                            Text("Unlocks at \(threshold)★")
                                .font(.footnote)
                                .foregroundStyle(Theme.glow)
                        }
                    }
                    selected.powerLineText
                        .font(Theme.display(14))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                    AbilityDemoView(character: selected)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18)
                            .stroke(.white.opacity(0.3), lineWidth: 1))
                        .frame(maxWidth: 540, maxHeight: 250)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
        .navigationTitle(Text("Abilities"))
        .navigationBarTitleDisplayMode(.inline)
        // One back affordance, the standard "‹", everywhere (owner ruling
        // 2026-08-01): the home push gets it from the system; the in-game
        // sheet supplies its own at the SAME spot (see MoonshotGameView).
    }

    private func characterPick(_ character: CharacterID) -> some View {
        Button {
            Haptics.tap()
            selected = character
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(isUnlocked(character) ? character.chipColor : Color.white.opacity(0.15))
                        .frame(width: 42, height: 42)
                    if !isUnlocked(character) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Circle()
                        .stroke(selected == character ? .white : .clear, lineWidth: 2)
                        .frame(width: 42, height: 42)
                }
                Text(LocalizedStringKey(character.displayNameKey))
                    .font(Theme.display(11))
                    .foregroundStyle(.white.opacity(selected == character ? 1 : 0.7))
            }
        }
        .accessibilityLabel(Text(LocalizedStringKey(character.displayNameKey)))
        .accessibilityValue(isUnlocked(character) ? Text("") : Text("Locked"))
    }

    private func isUnlocked(_ character: CharacterID) -> Bool {
        MoonshotRewards.isUnlocked(character, pool: pool)
    }

    private func threshold(_ character: CharacterID) -> Int? {
        MoonshotRewards.track.first { $0.grant == .character(character) }?.threshold
    }
}

#Preview {
    NavigationStack { AbilityDashboardView() }
        .modelContainer(try! Persistence.makeContainer(inMemory: true))
}
