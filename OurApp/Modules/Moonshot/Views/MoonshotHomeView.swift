import SwiftUI

/// Moonshot's front door: Campaign is live; Co-op and 1v1 show themselves
/// locked (M14 — the roadmap teases itself, one card flips live per slice).
struct MoonshotHomeView: View {
    /// Headless screenshot path: `-moonshotLevel N` jumps straight into
    /// level N (1-based). DEBUG-only, like the shell's launch args.
    @State private var debugLevelIndex: Int?

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-moonshotLevel"),
           arguments.indices.contains(flag + 1),
           let number = Int(arguments[flag + 1]) {
            _debugLevelIndex = State(initialValue: number - 1)
        }
        #endif
    }

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
        }
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
