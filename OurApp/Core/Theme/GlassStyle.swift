import SwiftUI

/// Frosted-glass surface used by the launcher drawer, tiles, and floating buttons.
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

#Preview {
    Text("Glass")
        .padding(40)
        .glassCard()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.duskGradient)
}
