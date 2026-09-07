import SwiftUI

/// A thumb pad. Deliberately plain in slice 1: the control scheme is an open
/// question in the module doc and is settled from the device, not from a
/// mockup — four rounds of mockups already failed to settle the look (F8), and
/// feel is even less answerable on paper than look was.
struct MoveJoystick: View {
    /// `(x: strafe, y: forward)`, each −1…1.
    var onChange: (SIMD2<Double>) -> Void

    @State private var knob: CGSize = .zero
    private let radius: CGFloat = 52

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial).frame(width: radius * 2, height: radius * 2)
            Circle().fill(.white.opacity(0.55)).frame(width: 44, height: 44)
                .offset(knob)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let raw = CGSize(width: value.translation.width,
                                     height: value.translation.height)
                    let length = sqrt(raw.width * raw.width + raw.height * raw.height)
                    let clamped = length > radius
                        ? CGSize(width: raw.width / length * radius,
                                 height: raw.height / length * radius)
                        : raw
                    knob = clamped
                    // Screen y grows downward; forward is up.
                    onChange(SIMD2(Double(clamped.width / radius),
                                   Double(-clamped.height / radius)))
                }
                .onEnded { _ in
                    knob = .zero
                    onChange(SIMD2(0, 0))
                }
        )
        .accessibilityHidden(true)
    }
}
