import SwiftUI

/// One date's icon: a rounded square in the icon's accent with a white glyph.
///
/// Deliberately **not** `HubIconView`. That one's sheen, floor shade and rim
/// are what make it read as designed at 78pt; at the ~34pt a row gives you the
/// same layers read as noise. This is the flattened cousin — one gradient, one
/// glyph.
struct DateIconView: View {
    let icon: DateIcon
    var size: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
            .fill(LinearGradient(colors: [icon.accent.light, icon.accent.deep],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                DateIconGlyph(icon: icon, side: size * 0.62)
            }
            .shadow(color: .black.opacity(0.18), radius: size * 0.07, y: size * 0.035)
            .accessibilityHidden(true)
    }
}

#Preview("Row size") {
    VStack(spacing: 10) {
        ForEach(Array(DateIcon.allCases.chunked(into: 6).enumerated()), id: \.offset) { _, row in
            HStack(spacing: 10) {
                ForEach(row, id: \.self) { DateIconView(icon: $0) }
            }
        }
    }
    .padding(24)
    .background(Theme.duskGradient)
}

#Preview("Large") {
    VStack(spacing: 14) {
        ForEach(Array(DateIcon.allCases.chunked(into: 4).enumerated()), id: \.offset) { _, row in
            HStack(spacing: 14) {
                ForEach(row, id: \.self) { DateIconView(icon: $0, size: 84) }
            }
        }
    }
    .padding(24)
    .background(Theme.duskGradient)
}

private extension Array {
    /// Preview-only helper: lay the twelve out in rows.
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
