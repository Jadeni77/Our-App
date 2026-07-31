import SwiftUI
import SwiftData

/// The relighting constellations (M1, M24): each world traces its own figure
/// across the sky — a swan, a drifting cloud, a lightning bolt — behind a
/// page-style pager. Cleared levels glow with their star count, the next
/// level pulses, locked ones wait dim, and a locked world dims whole with a
/// lock at its heart. Results come through @Query so a win recorded in the
/// pushed game view refreshes the map deterministically on pop-back.
struct LevelSelectView: View {
    @Query private var results: [MoonshotLevelResult]
    private let catalog = CampaignCatalog.bundled
    private let partnerID = MoonshotProgressStore.devicePartnerID
    @State private var world = 1
    @State private var pickedInitialWorld = false

    var body: some View {
        ZStack {
            DreamyBackground()
            TabView(selection: $world) {
                ForEach(1...max(catalog.worldCount, 1), id: \.self) { number in
                    WorldConstellationView(world: number, results: results)
                        .tag(number)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
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
        .onAppear {
            // Initial page only — onAppear refires on pop-back from a game,
            // and re-picking then would yank the pager mid-browse.
            guard !pickedInitialWorld else { return }
            pickedInitialWorld = true
            world = firstOpenWorld
            #if DEBUG
            // `-moonshotWorld N` pins the pager for headless screenshots —
            // swipes can't be scripted through simctl.
            let arguments = ProcessInfo.processInfo.arguments
            if let flag = arguments.firstIndex(of: "-moonshotWorld"),
               arguments.indices.contains(flag + 1),
               let forced = Int(arguments[flag + 1]) {
                world = forced
            }
            #endif
        }
    }

    /// The page a returning player wants: the world holding the next
    /// uncleared level they can actually play (everything cleared → the
    /// last world, where the campaign currently ends).
    private var firstOpenWorld: Int {
        let snapshots = results.map(\.snapshot)
        for index in catalog.levels.indices {
            let level = catalog.levels[index]
            let cleared = results.contains {
                $0.partnerID == partnerID && $0.levelID == level.id
                    && $0.mode == .solo && $0.cleared
            }
            if !cleared,
               catalog.isUnlocked(index: index, snapshots: snapshots, partnerID: partnerID) {
                return level.worldNumber
            }
        }
        return max(catalog.worldCount, 1)
    }
}

/// Per-world look: localized name, sky tint over the shared background,
/// and the normalized 12-node star path the world's levels sit on.
private struct WorldStyle {
    let name: LocalizedStringKey
    let tint: Color
    let points: [CGPoint]

    /// Worlds are authored contiguously from 1; anything beyond the table
    /// (never, today) reuses the last style rather than crashing the map.
    static func style(for world: Int) -> WorldStyle {
        styles[min(max(world, 1), styles.count) - 1]
    }

    private static let styles: [WorldStyle] = [
        WorldStyle(name: "The Moonlit Fields", tint: .clear, points: [
            .init(x: 0.08, y: 0.62), .init(x: 0.17, y: 0.44), .init(x: 0.26, y: 0.58),
            .init(x: 0.34, y: 0.36), .init(x: 0.43, y: 0.50), .init(x: 0.51, y: 0.30),
            .init(x: 0.58, y: 0.55), .init(x: 0.66, y: 0.38), .init(x: 0.74, y: 0.60),
            .init(x: 0.82, y: 0.42), .init(x: 0.89, y: 0.28), .init(x: 0.95, y: 0.52),
        ]),
        WorldStyle(name: "The Cloudfoam Skies", tint: .white.opacity(0.10), points: [
            .init(x: 0.08, y: 0.55), .init(x: 0.16, y: 0.40), .init(x: 0.26, y: 0.33),
            .init(x: 0.37, y: 0.30), .init(x: 0.48, y: 0.33), .init(x: 0.58, y: 0.30),
            .init(x: 0.68, y: 0.35), .init(x: 0.78, y: 0.42), .init(x: 0.86, y: 0.52),
            .init(x: 0.74, y: 0.62), .init(x: 0.55, y: 0.66), .init(x: 0.30, y: 0.64),
        ]),
        WorldStyle(name: "The Storm Heights", tint: Color.indigo.opacity(0.25), points: [
            .init(x: 0.12, y: 0.25), .init(x: 0.24, y: 0.35), .init(x: 0.34, y: 0.28),
            .init(x: 0.30, y: 0.48), .init(x: 0.44, y: 0.42), .init(x: 0.40, y: 0.62),
            .init(x: 0.56, y: 0.50), .init(x: 0.52, y: 0.72), .init(x: 0.68, y: 0.58),
            .init(x: 0.66, y: 0.80), .init(x: 0.82, y: 0.62), .init(x: 0.90, y: 0.82),
        ]),
    ]
}

/// One pager page: a world's twelve stars on its own path, its name and
/// banked stars up top, all of it dimmed behind a lock until the previous
/// world's finale falls (the gate IS the linear rule — M24).
private struct WorldConstellationView: View {
    let world: Int
    let results: [MoonshotLevelResult]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let catalog = CampaignCatalog.bundled
    private let partnerID = MoonshotProgressStore.devicePartnerID

    var body: some View {
        let style = WorldStyle.style(for: world)
        let snapshots = results.map(\.snapshot)
        let worldLevels = catalog.levels(inWorld: world)
        let unlocked = catalog.isWorldUnlocked(world, snapshots: snapshots, partnerID: partnerID)

        ZStack {
            style.tint.ignoresSafeArea()

            VStack(spacing: 0) {
                header(style: style, worldLevels: worldLevels)
                constellation(style: style, worldLevels: worldLevels, snapshots: snapshots)
                    .padding(24)
            }
            .opacity(unlocked ? 1 : 0.25)
            .allowsHitTesting(unlocked)

            if !unlocked {
                VStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white.opacity(0.8))
                    Text(style.name)
                        .font(Theme.display(20))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func header(style: WorldStyle, worldLevels: [MoonshotLevel]) -> some View {
        let stars = worldLevels.reduce(0) { sum, level in
            sum + (results.first {
                $0.partnerID == partnerID && $0.levelID == level.id && $0.mode == .solo
            }?.bestStars ?? 0)
        }
        return VStack(spacing: 2) {
            Text(style.name)
                .font(Theme.display(22))
                .foregroundStyle(.white)
            Text("\(stars)★")
                .font(Theme.display(14))
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
    }

    private func constellation(style: WorldStyle,
                               worldLevels: [MoonshotLevel],
                               snapshots: [LevelResultSnapshot]) -> some View {
        GeometryReader { geometry in
            let size = geometry.size
            let points = style.points.map {
                CGPoint(x: $0.x * size.width, y: $0.y * size.height)
            }

            connectingLines(points)

            // zip: a hypothetical 13th level falls off the map instead
            // of crashing the index into the 12-point star path.
            ForEach(Array(zip(worldLevels, points)), id: \.0.id) { level, point in
                if let index = catalog.globalIndex(of: level) {
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
                        .position(point)
                }
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
