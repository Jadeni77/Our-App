import SwiftUI
import SwiftData

/// The relighting constellation (M1): twelve stars trace a swan across the
/// sky — cleared levels glow with their star count, the next level pulses,
/// locked ones wait dim. Results come through @Query so a win recorded in
/// the pushed game view refreshes the map deterministically on pop-back.
struct LevelSelectView: View {
    @Query private var results: [MoonshotLevelResult]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let catalog = CampaignCatalog.bundled
    private let partnerID = MoonshotProgressStore.devicePartnerID

    /// Normalized swan-path positions for the twelve levels.
    private let starPoints: [CGPoint] = [
        .init(x: 0.08, y: 0.62), .init(x: 0.17, y: 0.44), .init(x: 0.26, y: 0.58),
        .init(x: 0.34, y: 0.36), .init(x: 0.43, y: 0.50), .init(x: 0.51, y: 0.30),
        .init(x: 0.58, y: 0.55), .init(x: 0.66, y: 0.38), .init(x: 0.74, y: 0.60),
        .init(x: 0.82, y: 0.42), .init(x: 0.89, y: 0.28), .init(x: 0.95, y: 0.52),
    ]

    var body: some View {
        ZStack {
            DreamyBackground()
            let snapshots = results.map(\.snapshot)
            GeometryReader { geometry in
                let size = geometry.size
                let points = starPoints.map {
                    CGPoint(x: $0.x * size.width, y: $0.y * size.height)
                }

                connectingLines(points)

                ForEach(catalog.levels.indices, id: \.self) { index in
                    let level = catalog.levels[index]
                    let unlocked = catalog.isUnlocked(index: index,
                                                      snapshots: snapshots,
                                                      partnerID: partnerID)
                    let result = results.first {
                        $0.partnerID == partnerID && $0.levelID == level.id && $0.mode == .solo
                    }
                    let cleared = result?.cleared == true
                    starNode(index: index,
                             cleared: cleared,
                             stars: result?.bestStars ?? 0,
                             unlocked: unlocked,
                             isNext: unlocked && !cleared)
                        .position(points[index])
                }
            }
            .padding(24)
        }
        .navigationTitle(Text("Campaign"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    RewardTrackView()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "gift.fill")
                        Text("\(MoonshotRewards.starPool(results.map(\.snapshot)))★")
                            .fixedSize()
                    }
                    .font(Theme.display(15))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassCard(cornerRadius: 14)
                }
                .accessibilityLabel(Text("Reward track"))
            }
        }
    }

    private func connectingLines(_ points: [CGPoint]) -> some View {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
        .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [1, 5]))
    }

    @ViewBuilder
    private func starNode(index: Int, cleared: Bool, stars: Int, unlocked: Bool, isNext: Bool) -> some View {
        let node = VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(cleared ? Theme.glow : Color.white.opacity(unlocked ? 0.32 : 0.14))
                    .frame(width: 44, height: 44)
                    .shadow(color: cleared ? Theme.glow.opacity(0.8) : .clear, radius: 10)
                if cleared {
                    Text("\(index + 1)")
                        .font(Theme.display(17))
                        .foregroundStyle(Color(red: 0.35, green: 0.3, blue: 0.2))
                } else if unlocked {
                    Text("\(index + 1)")
                        .font(Theme.display(17))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            if cleared {
                miniStars(stars)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cleared
            ? Text("Level \(index + 1), \(stars) stars")
            : (unlocked ? Text("Level \(index + 1)") : Text("Level \(index + 1), locked")))

        if unlocked {
            NavigationLink {
                MoonshotGameView(levelIndex: index)
            } label: {
                node.modifier(NextLevelPulse(active: isNext && !reduceMotion))
            }
            .buttonStyle(.plain)
        } else {
            node
        }
    }

    private func miniStars(_ stars: Int) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<3) { i in
                Image(systemName: i < stars ? "star.fill" : "star")
                    .font(.system(size: 8))
                    .foregroundStyle(i < stars ? Color.yellow : .white.opacity(0.4))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A slow breathing scale on the next level to play; static under Reduce
/// Motion (the brighter fill already marks it).
private struct NextLevelPulse: ViewModifier {
    let active: Bool
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(active && pulsing ? 1.12 : 1)
            .animation(active ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true) : .default,
                       value: pulsing)
            .onAppear { pulsing = true }
    }
}

#Preview {
    NavigationStack { LevelSelectView() }
        .modelContainer(try! Persistence.makeContainer(inMemory: true))
}
