import SwiftUI

/// The one place a grant names itself — the track, the win overlay, and
/// the strip all read from here (Views-layer: Rules stays UI-free).
extension RewardGrant {
    var titleText: Text {
        switch self {
        case .trail(.stardust): Text("Stardust")
        case .trail(.petals): Text("Petals")
        case .trail(.aurora): Text("Aurora")
        case .trail(.nebula): Text("Nebula")
        case .trail(.comet): Text("Comet")
        case .character(let character): Text(LocalizedStringKey(character.displayNameKey))
        case .theme(.dawn): Text("Dawn veil")
        case .theme(.midnight): Text("Midnight")
        case .skin(.golden): Text("Golden slingshot")
        case .skin(.obsidian): Text("Obsidian slingshot")
        }
    }

    /// The one line that says what a grant DOES (owner: "what do these
    /// rewards even do?") — every track row wears it under the name.
    var purposeText: Text {
        switch self {
        case .trail: Text("A sparkle your star wears in flight")
        case .character(let character): character.powerLineText
        case .theme: Text("Re-tints the campaign map")
        case .skin: Text("Dresses the slingshot")
        }
    }
}

/// "[gift] Nox · 3★ to go ▬▬▬░░" — the next unlock, always visible (M26).
/// Renders nothing once the track is complete.
struct NextUnlockStrip: View {
    let pool: Int

    var body: some View {
        if let next = MoonshotRewards.nextMilestone(pool: pool) {
            let floor = MoonshotRewards.previousThreshold(pool: pool)
            let span = max(next.threshold - floor, 1)
            let fraction = max(0, min(1, Double(pool - floor) / Double(span)))
            HStack(spacing: 10) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.glow)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        next.grant.titleText
                            .font(Theme.display(13))
                            .foregroundStyle(.white)
                        Text("\(next.threshold - pool)★ to go")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.2))
                            Capsule().fill(Theme.glow)
                                .frame(width: max(6, geometry.size.width * fraction))
                        }
                    }
                    .frame(height: 5)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassCard(cornerRadius: 16)
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview {
    ZStack {
        DreamyBackground()
        NextUnlockStrip(pool: 21).frame(width: 260)
    }
}
