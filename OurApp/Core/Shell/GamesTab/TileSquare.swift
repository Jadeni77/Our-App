import SwiftUI

/// The one springboard icon square: every tile kind renders its face inside
/// this fixed 1:1 cell, so module and external tiles cannot drift apart in
/// size — the content lives in an overlay and never negotiates with the grid.
struct TileSquare<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .overlay { content }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .glassCard(cornerRadius: 20)
    }
}

#Preview {
    HStack(spacing: 18) {
        TileSquare { Text("🍽️").font(.system(size: 40)) }
        TileSquare { Color.orange }
    }
    .padding(40)
    .background(Theme.duskGradient)
}
