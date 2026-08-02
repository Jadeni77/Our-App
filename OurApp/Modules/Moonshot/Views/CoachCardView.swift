import SwiftUI

/// One character's card (M25, rebuilt 2026-08-02): the coach shows it once
/// when a character is first met or unlocked, and it now DEMONSTRATES —
/// the same live physics loop as the abilities dashboard, not a page of
/// docs (owner amendment). The X is the only door out; the loop runs
/// until the player closes it themselves.
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
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(character.chipColor)
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1.5))
                        .shadow(color: character.chipColor.opacity(0.7), radius: 8)
                    Text(LocalizedStringKey(character.displayNameKey))
                        .font(Theme.display(24))
                        .foregroundStyle(.white)
                }
                AbilityDemoView(character: character)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(.white.opacity(0.3), lineWidth: 1))
                    .frame(width: 360, height: 165)
                powerLine
                    .font(Theme.display(14))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if unlocked {
                    Text("Tap mid-flight to use it")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                    if character == .nox {
                        // The celebration must not over-promise (review
                        // finding): 24★ grants summonability, not a
                        // roster slot.
                        Text("Summon him from the star picker — 40 moondust a visit")
                            .font(.footnote)
                            .foregroundStyle(Theme.glow)
                            .multilineTextAlignment(.center)
                    }
                } else if let threshold = unlockThreshold {
                    Text("Unlocks at \(threshold)★")
                        .font(.footnote)
                        .foregroundStyle(Theme.glow)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 16)
            .glassCard(cornerRadius: 28)
            .overlay(alignment: .topTrailing) {
                CardCloseButton(onDismiss: onDismiss)
            }
            .frame(maxWidth: 440)
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

/// A gloom kind's card (owner amendment 2026-08-02): the first meeting
/// blocks mid-level with the most natural attack FAILING on loop; the
/// caption names the counter-move, the X is the only door out. Replaces
/// the one-line fading banner those kinds used to get.
struct GloomIntroCardView: View {
    let kind: GloomKind
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {}
            VStack(spacing: 10) {
                GloomDemoView(kind: kind)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(.white.opacity(0.3), lineWidth: 1))
                    .frame(width: 360, height: 165)
                counterLine
                    .font(Theme.display(15))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 16)
            .glassCard(cornerRadius: 28)
            .overlay(alignment: .topTrailing) {
                CardCloseButton(onDismiss: onDismiss)
            }
            .frame(maxWidth: 440)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction { onDismiss() }
            .accessibilityAction(.escape) { onDismiss() }
        }
    }

    /// The lesson the demo can't say out loud — same copy the old banners
    /// taught, one line per kind.
    private var counterLine: Text {
        switch kind {
        case .shield: Text("Its shell breaks first — hit it twice")
        case .hopper: Text("It jumps when you land close — bait it")
        case .mist: Text("Only a power can touch the mist")
        case .great: Text("The Great Gloom shrugs — chip away")
        case .helmet: Text("The helmet shrugs off sky-hits — strike from the side")
        }
    }
}

/// The one door out of a teaching card (owner: "until the user manually
/// presses X") — shared by both card kinds.
private struct CardCloseButton: View {
    let onDismiss: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            onDismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.85), .white.opacity(0.25))
                .padding(10)
        }
        .accessibilityLabel(Text("Close"))
    }
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
        case .pogo: Text("Bounce — turn rubbery and ricochet at full speed")
        }
    }
}

#Preview("Character") {
    CoachCardView(character: .nox, unlocked: true) {}
}

#Preview("Gloom") {
    GloomIntroCardView(kind: .helmet) {}
}
