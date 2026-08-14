import SwiftData
import SwiftUI

/// Where a co-op game starts, and where you find out whose go it is.
///
/// It is mostly a list of levels with a line of state each, because the game is
/// turn-based across distance: most of the time you arrive here to see whether
/// she has played, not to start something.
struct CoopLobbyView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: CoopMatch.live) private var matches: [CoopMatch]

    private let catalog = CampaignCatalog.bundled
    private var me: String { LocalAuthor.id() }

    var body: some View {
        ZStack {
            DreamyBackground()
            if !SyncSecretStore.isPaired {
                needsPairing
            } else {
                levels
            }
        }
        .navigationDestination(for: UUID.self) { levelID in
            if let level = catalog.levels.first(where: { $0.id == levelID }) {
                CoopMatchView(level: level)
            }
        }
        .navigationTitle(Text("Co-op"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    /// Co-op is meaningless alone, so this is a dead end worth explaining
    /// rather than an empty list (principle 7).
    private var needsPairing: some View {
        VStack(spacing: 14) {
            Text(verbatim: "🤝").font(.system(size: 38))
            Text("Pair your phones first — co-op needs both of you")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    private var levels: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(Array(catalog.levels.enumerated()), id: \.element.id) { index, level in
                    // **Value-based, not a destination closure.** A
                    // `NavigationLink { CoopMatchView(level:) }` inside a
                    // ForEach has its destination evaluated *eagerly*, so every
                    // row built a whole match view — each with its own
                    // `@Query` — during the lobby's own body evaluation. The
                    // resulting invalidation cascade re-ran body, rebuilt them
                    // all, and froze the app. A sample showed CoopMatchView on
                    // the stack 224 times, nested.
                    NavigationLink(value: level.id) {
                        row(for: level, number: index + 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    private func row(for level: MoonshotLevel, number: Int) -> some View {
        let match = matches.first { $0.levelID == level.id }
        return HStack(spacing: 10) {
            Text(verbatim: "\(number)")
                .font(Theme.display(16))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 26)
            Text(verbatim: level.title ?? "")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            status(for: match)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassCard(cornerRadius: 16)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func status(for match: CoopMatch?) -> some View {
        if let match {
            // Whose go it is, which is the only thing you came here to learn.
            Text(match.turnHolder == me ? "Your turn" : "Her turn")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(match.turnHolder == me ? 0.95 : 0.6))
        } else {
            Text("Start")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))
        }
    }
}
