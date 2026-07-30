import SwiftUI

/// A folder-style collection: the same glass square holding up to nine member
/// emojis in a 3×3 mini-grid, the user's name beneath (S6 — shown verbatim).
struct CollectionTileView: View {
    let collection: GamesLayout.Collection
    let store: GamesLayoutStore
    @Environment(ArtworkStore.self) private var artwork

    private let miniColumns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: miniColumns, spacing: 2) {
                ForEach(collection.members.prefix(9), id: \.self) { memberID in
                    memberGlyph(memberID)
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
        .task(id: collection.members) {
            // Pull cached icons for external members into memory so the
            // mini-grid can render them without touching disk in `body`.
            for member in collection.members.prefix(9) {
                if let external = store.externalApp(forKey: member) {
                    await artwork.loadIfNeeded(external.id)
                }
            }
        }
    }

    /// An external member with cached artwork shows its real icon in the
    /// mini-grid (S7); everything else shows its emoji glyph.
    @ViewBuilder
    private func memberGlyph(_ memberID: String) -> some View {
        if let external = store.externalApp(forKey: memberID),
           let image = artwork.image(for: external.id) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            Text(store.glyph(forMember: memberID))
                .font(.system(size: 15))
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
    .environment(ArtworkStore(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("preview-artwork")))
}
