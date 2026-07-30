import SwiftUI

/// One external app on the springboard (S7): artwork when cached, the
/// fallback emoji otherwise, the user's name beneath — visually a sibling
/// of `AppTileView`.
struct ExternalTileView: View {
    let app: GamesLayout.ExternalApp

    var body: some View {
        VStack(spacing: 8) {
            Text(app.emoji)
                .font(.system(size: 40))
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .glassCard(cornerRadius: 20)
            Text(verbatim: app.name)   // user data (S6)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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
}
