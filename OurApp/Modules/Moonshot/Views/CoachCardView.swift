import SwiftUI

/// One character's card (M25): the coach shows it once when a character is
/// first met — in a queue or at the swap chip — and the home dashboard
/// (owner amendment 2026-07-31) opens it any time as a reference.
struct CoachCardView: View {
    let character: CharacterID
    let unlocked: Bool
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // The dimmer BLOCKS touches, never dismisses — an accidental
            // tap must not burn a once-ever teaching moment (review call).
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {}
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(character.chipColor)
                        .frame(width: 72, height: 72)
                        .shadow(color: character.chipColor.opacity(0.7), radius: 14)
                    Circle()
                        .stroke(.white.opacity(0.85), lineWidth: 2)
                        .frame(width: 72, height: 72)
                }
                Text(LocalizedStringKey(character.displayNameKey))
                    .font(Theme.display(26))
                    .foregroundStyle(.white)
                powerLine
                    .font(Theme.display(15))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if unlocked {
                    Text("Tap mid-flight to use it")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                    Button {
                        Haptics.tap()
                        onDismiss()
                    } label: {
                        Text("Let's go")
                            .font(Theme.display(16))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 26)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Theme.indigo))
                    }
                } else {
                    if let threshold = unlockThreshold {
                        Text("Unlocks at \(threshold)★")
                            .font(.footnote)
                            .foregroundStyle(Theme.glow)
                    }
                    Button {
                        Haptics.tap()
                        onDismiss()
                    } label: {
                        Text("Close")
                            .font(Theme.display(16))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 26)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.white.opacity(0.2)))
                    }
                }
            }
            .padding(30)
            .glassCard(cornerRadius: 28)
            .frame(maxWidth: 420)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isModal)
            // .combine may not forward the child button's action reliably —
            // give VoiceOver an explicit activate and escape (review fix).
            .accessibilityAction { onDismiss() }
            .accessibilityAction(.escape) { onDismiss() }
        }
    }

    private var unlockThreshold: Int? {
        MoonshotRewards.track.first { $0.grant == .character(character) }?.threshold
    }

    private var powerLine: Text { character.powerLineText }
}

extension CharacterID {
    /// The one line that says what this star DOES — the coach card and the
    /// abilities dashboard both read from here.
    var powerLineText: Text {
        switch self {
        case .mochi: Text("Moon Slam — stop mid-air and drop like the moon")
        case .zip: Text("Comet Dash — a burst of speed, ×2 vs crystal and wood")
        case .twinkle: Text("Split — one star becomes two")
        case .nox: Text("Gravity Well — freeze and pull the world in")
        case .misty: Text("Phase — turn to mist, slip through one piece")
        }
    }
}

#Preview {
    CoachCardView(character: .nox, unlocked: true) {}
}
