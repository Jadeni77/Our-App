import SwiftUI
import SwiftData

/// Level picker v0: a plain list with lock and star states. The campaign PR
/// replaces this list with the relighting constellation (M1). Results come
/// through @Query so a win recorded in the pushed game view refreshes the
/// list deterministically on pop-back.
struct LevelSelectView: View {
    @Query private var results: [MoonshotLevelResult]
    private let catalog = CampaignCatalog.bundled
    private let partnerID = MoonshotProgressStore.devicePartnerID

    var body: some View {
        ZStack {
            DreamyBackground()
            let snapshots = results.map(\.snapshot)
            List(catalog.levels.indices, id: \.self) { index in
                let level = catalog.levels[index]
                let unlocked = catalog.isUnlocked(index: index,
                                                  snapshots: snapshots,
                                                  partnerID: partnerID)
                let result = results.first {
                    $0.partnerID == partnerID && $0.levelID == level.id && $0.mode == .solo
                }
                let row = HStack {
                    Text("Level \(index + 1)")
                        .font(Theme.display(18))
                    Spacer()
                    if let result, result.cleared {
                        starRow(result.bestStars)
                    } else if !unlocked {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                Group {
                    if unlocked {
                        NavigationLink { MoonshotGameView(levelIndex: index) } label: { row }
                    } else {
                        row
                    }
                }
                .listRowBackground(Color.white.opacity(unlocked ? 0.25 : 0.12))
                .opacity(unlocked ? 1 : 0.5)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(Text("Campaign"))
    }

    private func starRow(_ stars: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<3) { i in
                Image(systemName: i < stars ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle(i < stars ? Color.yellow : .secondary)
            }
        }
        .accessibilityLabel(Text("\(stars) stars"))
    }
}

#Preview {
    NavigationStack { LevelSelectView() }
        .modelContainer(try! Persistence.makeContainer(inMemory: true))
}
