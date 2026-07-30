import SwiftUI

/// A folder-style collection: the same glass square holding up to nine member
/// emojis in a 3×3 mini-grid, the user's name beneath (S6 — shown verbatim).
struct CollectionTileView: View {
    let collection: GamesLayout.Collection
    let store: GamesLayoutStore

    private let miniColumns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: miniColumns, spacing: 2) {
                ForEach(collection.members.prefix(9), id: \.self) { memberID in
                    Text(store.module(for: memberID)?.emoji ?? "")
                        .font(.system(size: 15))
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .glassCard(cornerRadius: 20)
            Text(collection.name)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

#Preview {
    let modules = [FoodDecisionModule.descriptor]
    CollectionTileView(
        collection: .init(id: UUID(), name: "Ours 💗",
                          members: ["food-decision"]),
        store: GamesLayoutStore(
            modules: modules,
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("preview-layout.json")))
    .frame(width: 88)
    .padding(40)
    .background(Theme.duskGradient)
}
