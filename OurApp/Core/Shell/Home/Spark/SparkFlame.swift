import SwiftUI

/// The 火花 itself, drawn rather than borrowed — principle 9, and the reason the
/// hub tiles stopped using emoji: an emoji flame is somebody else's artwork and
/// reads as casual next to a day counter.
///
/// One teardrop-with-a-curl outer body and an inner core, sized to a unit
/// square and scaled by the caller.
struct SparkFlame: View {
    /// Lit means checked in today. Unlit is the same silhouette in outline, so
    /// the shape reads as one object in two states rather than two icons.
    var isLit: Bool
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            if isLit {
                body(for: .fill)
                core
            } else {
                body(for: .stroke)
            }
        }
        .frame(width: size, height: size)
        // Not `repeatForever`. An active repeating animation also sweeps in any
        // geometry change its view receives, and this pill sits inside the
        // hero's subtree — which is exactly how the paired hearts ended up
        // oscillating between two positions forever.
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isLit)
    }

    private enum Rendering { case fill, stroke }

    @ViewBuilder
    private func body(for rendering: Rendering) -> some View {
        let shape = FlameShape()
        switch rendering {
        case .fill:
            shape.fill(
                LinearGradient(colors: [Theme.peach,
                                        Theme.rose,
                                        Color(red: 0.84, green: 0.47, blue: 0.62)],
                               startPoint: .bottom, endPoint: .top))
        case .stroke:
            shape.stroke(.white.opacity(0.55), lineWidth: size * 0.07)
        }
    }

    /// The hot centre, sitting low and slightly right of the leaning tip.
    private var core: some View {
        FlameShape()
            .fill(.white.opacity(0.5))
            .frame(width: size * 0.34, height: size * 0.40)
            .offset(x: -size * 0.02, y: size * 0.22)
            .blur(radius: size * 0.03)
    }
}

/// The silhouette. **A single-lobe teardrop reads as a water drop, not fire** —
/// two attempts did exactly that, the same way an earlier icon read as a
/// lollipop. What fixes it is not proportion or lean but the **notched top**: a
/// tall main tip, a shorter secondary lick, and a valley between them. No
/// droplet has that, so nothing else has to carry the meaning.
///
/// Judged by rendering the bezier path on its own at high resolution rather
/// than by rebuilding the app each time — a silhouette that fails at 22pt
/// usually fails at 200pt too, and the loop is seconds instead of minutes.
private struct FlameShape: Shape {
    func path(in rect: CGRect) -> Path {
        /// Unit coordinates, so the shape is defined once and scales cleanly.
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var path = Path()
        path.move(to: point(0.50, 1.00))
        // Right side of the bulb, swelling out.
        path.addCurve(to: point(0.88, 0.56),
                      control1: point(0.84, 1.00), control2: point(0.94, 0.78))
        // Up to the shorter, secondary lick.
        path.addCurve(to: point(0.76, 0.20),
                      control1: point(0.86, 0.40), control2: point(0.80, 0.31))
        // Down into the valley between the two licks. **This is the cue that
        // does the work** — no droplet has a notch in its top.
        path.addCurve(to: point(0.60, 0.34),
                      control1: point(0.72, 0.30), control2: point(0.66, 0.31))
        // Up to the main tip, landing left of centre so the flame leans.
        path.addCurve(to: point(0.42, 0.00),
                      control1: point(0.58, 0.20), control2: point(0.50, 0.12))
        // Down the inside of the main tip.
        path.addCurve(to: point(0.30, 0.36),
                      control1: point(0.36, 0.16), control2: point(0.34, 0.26))
        // Out to the left foot.
        path.addCurve(to: point(0.10, 0.68),
                      control1: point(0.24, 0.50), control2: point(0.10, 0.52))
        path.addCurve(to: point(0.50, 1.00),
                      control1: point(0.10, 0.86), control2: point(0.26, 1.00))
        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack {
        DreamyBackground(showsMoon: false)
        HStack(spacing: 30) {
            SparkFlame(isLit: false, size: 60)
            SparkFlame(isLit: true, size: 60)
        }
    }
}
