import SwiftUI

/// One external app on the springboard (S7): official artwork when cached,
/// the fallback emoji otherwise, the user's name beneath — visually a
/// sibling of `AppTileView`.
struct ExternalTileView: View {
    let app: GamesLayout.ExternalApp
    @Environment(ArtworkStore.self) private var artwork

    var body: some View {
        VStack(spacing: 8) {
            TileSquare {
                if let image = artwork.image(for: app.id) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Text(app.emoji)
                        .font(.system(size: 40))
                }
            }
            Text(verbatim: app.name)   // user data (S6)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .task(id: app.artworkURL) {
            // Load the cached icon off the main render path; if a persisted
            // artworkURL never got its download, self-heal it here.
            await artwork.loadIfNeeded(app.id)
            if artwork.image(for: app.id) == nil, let url = app.artworkURL {
                await artwork.fetchArtwork(from: url, for: app.id)
            }
        }
    }
}

#Preview {
    ExternalTileView(app: .init(
        id: UUID(), name: "Identity V", emoji: "🎮",
        artworkURL: nil, launchURL: URL(string: "identityv://"), storeURL: nil))
    .frame(width: 88)
    .padding(40)
    .background(Theme.duskGradient)
    .environment(ArtworkStore(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("preview-artwork")))
}
