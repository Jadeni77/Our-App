import SwiftUI

/// One hub icon: a squircle in the topic's accent, with the layered depth that
/// separates "a coloured square with a shape on it" from something that looks
/// designed — a sheen across the top third, a shade settling into the bottom
/// edge, a hairline rim, and a soft shadow onto the panel.
///
/// Everything scales off `side`, so one definition serves the 78pt tile, the
/// previews, and any future size.
struct HubIconView: View {
    let icon: HubIcon

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let shape = RoundedRectangle(cornerRadius: side * 0.26, style: .continuous)

            ZStack {
                LinearGradient(colors: [icon.ramp.light, icon.ramp.mid, icon.ramp.deep],
                               startPoint: .topLeading, endPoint: .bottomTrailing)

                // Weight settling at the bottom; without it the fill reads flat.
                LinearGradient(colors: [.clear, .black.opacity(0.18)],
                               startPoint: .center, endPoint: .bottom)

                sheen(side: side)
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(.white.opacity(0.45), lineWidth: max(1, side * 0.013))
            }
            .overlay {
                HubIconGlyph(icon: icon, side: side)
                    .accessibilityHidden(true)
            }
            .shadow(color: .black.opacity(0.22), radius: side * 0.09, y: side * 0.045)
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// A wide, shallow ellipse riding above the top edge: light falling on a
    /// rounded body, rather than a flat band across it.
    private func sheen(side: CGFloat) -> some View {
        Ellipse()
            .fill(LinearGradient(colors: [.white.opacity(0.50), .white.opacity(0.05)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: side * 1.15, height: side * 0.62)
            .offset(y: -side * 0.30)
            .blur(radius: side * 0.02)
    }
}

#Preview {
    HStack(spacing: 18) {
        ForEach(Array(HubIcon.allCases.enumerated()), id: \.offset) { _, icon in
            HubIconView(icon: icon).frame(width: 78, height: 78)
        }
    }
    .padding(30)
    .background(Theme.duskGradient)
}
