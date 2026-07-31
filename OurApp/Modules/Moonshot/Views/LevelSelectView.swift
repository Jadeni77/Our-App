import SwiftUI
import SwiftData

/// Level picker v0: a plain list with lock and star states. The engine PR
/// wires row taps into the game scene; the campaign PR replaces this list
/// with the relighting constellation (M1).
struct LevelSelectView: View {
    @Environment(\.modelContext) private var modelContext
    private let catalog = CampaignCatalog.load()

    var body: some View {
        ZStack {
            DreamyBackground()
            let store = MoonshotProgressStore(context: modelContext)
            let snapshots = store.snapshots()
            List(catalog.levels.indices, id: \.self) { index in
                let level = catalog.levels[index]
                let unlocked = catalog.isUnlocked(index: index,
                                                  snapshots: snapshots,
                                                  partnerID: store.partnerID)
                let result = store.result(for: level.id)
                HStack {
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
