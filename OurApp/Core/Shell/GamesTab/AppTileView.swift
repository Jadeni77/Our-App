import SwiftUI

/// One springboard app: emoji in a glass square, localized name beneath —
/// visually continuous with the retired rail's tiles.
struct AppTileView: View {
    let module: ModuleDescriptor

    var body: some View {
        VStack(spacing: 8) {
            TileSquare {
                Text(module.emoji)
                    .font(.system(size: 40))
            }
            Text(module.name)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

#Preview {
    AppTileView(module: FoodDecisionModule.descriptor)
        .frame(width: 88)
        .padding(40)
        .background(Theme.duskGradient)
}
