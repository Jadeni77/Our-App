import SwiftUI

/// The twelve glyphs, composed as views rather than one `Shape`.
///
/// Views, deliberately: several of these need a hole (the ring, the camera
/// lens, the pin), and punching one from a single `Path` means relying on
/// subpath winding — the trap that produced a notch in the hub bubble's tail.
/// `strokeBorder` and `blendMode(.destinationOut)` are unambiguous.
///
/// Everything scales off `side`, so one definition serves the 34pt row icon,
/// the picker grid and the previews.
struct DateIconGlyph: View {
    let icon: DateIcon
    let side: CGFloat

    var body: some View {
        Group {
            switch icon {
            case .cake:       cake
            case .plane:      plane
            case .home:       house
            case .ring:       ring
            case .heart:      HeartShape().fill(.white)
                                  .frame(width: side * 0.52, height: side * 0.47)
            case .gift:       gift
            case .camera:     camera
            case .star:       SparkleShape().fill(.white)
                                  .frame(width: side * 0.58, height: side * 0.58)
            case .wave:       wave
            case .graduation: graduation
            case .flower:     flower
            case .pin:        pin
            }
        }
        .frame(width: side, height: side)
    }

    private var cake: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.05, style: .continuous)
                .fill(.white)
                .frame(width: side * 0.60, height: side * 0.20)
                .offset(y: side * 0.16)
            RoundedRectangle(cornerRadius: side * 0.06, style: .continuous)
                .fill(.white.opacity(0.78))
                .frame(width: side * 0.48, height: side * 0.16)
                .offset(y: -side * 0.01)
            Capsule().fill(.white)
                .frame(width: side * 0.05, height: side * 0.12)
                .offset(y: -side * 0.16)
            Circle().fill(.white)
                .frame(width: side * 0.09, height: side * 0.09)
                .offset(y: -side * 0.26)
        }
    }

    private var plane: some View {
        Path { path in
            path.move(to: CGPoint(x: side * 0.06, y: side * 0.56))
            path.addLine(to: CGPoint(x: side * 0.94, y: side * 0.22))
            path.addLine(to: CGPoint(x: side * 0.70, y: side * 0.58))
            path.addLine(to: CGPoint(x: side * 0.86, y: side * 0.84))
            path.addLine(to: CGPoint(x: side * 0.58, y: side * 0.70))
            path.addLine(to: CGPoint(x: side * 0.30, y: side * 0.88))
            path.addLine(to: CGPoint(x: side * 0.36, y: side * 0.62))
            path.closeSubpath()
        }
        .fill(.white)
    }

    private var house: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: side * 0.50, y: side * 0.16))
                path.addLine(to: CGPoint(x: side * 0.90, y: side * 0.47))
                path.addLine(to: CGPoint(x: side * 0.10, y: side * 0.47))
                path.closeSubpath()
            }
            .fill(.white)
            RoundedRectangle(cornerRadius: side * 0.04, style: .continuous)
                .fill(.white)
                .frame(width: side * 0.52, height: side * 0.32)
                .offset(y: side * 0.14)
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .strokeBorder(.white, lineWidth: side * 0.11)
                .frame(width: side * 0.56, height: side * 0.56)
                .offset(y: side * 0.12)
            // The gem overlaps the band's top edge. Floated clear of it, the
            // pair reads as a lollipop rather than a ring.
            Path { path in
                path.move(to: CGPoint(x: side * 0.50, y: side * 0.12))
                path.addLine(to: CGPoint(x: side * 0.66, y: side * 0.34))
                path.addLine(to: CGPoint(x: side * 0.50, y: side * 0.44))
                path.addLine(to: CGPoint(x: side * 0.34, y: side * 0.34))
                path.closeSubpath()
            }
            .fill(.white)
        }
    }

    private var gift: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.05, style: .continuous)
                .fill(.white)
                .frame(width: side * 0.62, height: side * 0.40)
                .offset(y: side * 0.16)
            Rectangle()
                .fill(.white.opacity(0.60))
                .frame(width: side * 0.10, height: side * 0.40)
                .offset(y: side * 0.16)
            RoundedRectangle(cornerRadius: side * 0.03, style: .continuous)
                .fill(.white)
                .frame(width: side * 0.70, height: side * 0.12)
                .offset(y: -side * 0.09)
            Circle().strokeBorder(.white, lineWidth: side * 0.05)
                .frame(width: side * 0.19, height: side * 0.19)
                .offset(x: -side * 0.10, y: -side * 0.21)
            Circle().strokeBorder(.white, lineWidth: side * 0.05)
                .frame(width: side * 0.19, height: side * 0.19)
                .offset(x: side * 0.10, y: -side * 0.21)
        }
    }

    private var camera: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.09, style: .continuous)
                .fill(.white)
                .frame(width: side * 0.74, height: side * 0.48)
                .offset(y: side * 0.07)
            RoundedRectangle(cornerRadius: side * 0.03, style: .continuous)
                .fill(.white)
                .frame(width: side * 0.24, height: side * 0.10)
                .offset(x: -side * 0.16, y: -side * 0.20)
        }
        .compositingGroup()
        .overlay {
            // Punched out, so the tile's gradient shows through as the lens.
            Circle()
                .frame(width: side * 0.22, height: side * 0.22)
                .offset(y: side * 0.07)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
    }

    private var wave: some View {
        Path { path in
            for row in 0..<2 {
                let y = side * (0.40 + Double(row) * 0.22)
                path.move(to: CGPoint(x: side * 0.12, y: y))
                path.addCurve(to: CGPoint(x: side * 0.50, y: y),
                              control1: CGPoint(x: side * 0.24, y: y - side * 0.11),
                              control2: CGPoint(x: side * 0.38, y: y + side * 0.11))
                path.addCurve(to: CGPoint(x: side * 0.88, y: y),
                              control1: CGPoint(x: side * 0.62, y: y - side * 0.11),
                              control2: CGPoint(x: side * 0.76, y: y + side * 0.11))
            }
        }
        .stroke(.white, style: StrokeStyle(lineWidth: side * 0.09, lineCap: .round))
    }

    private var graduation: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: side * 0.50, y: side * 0.20))
                path.addLine(to: CGPoint(x: side * 0.94, y: side * 0.40))
                path.addLine(to: CGPoint(x: side * 0.50, y: side * 0.60))
                path.addLine(to: CGPoint(x: side * 0.06, y: side * 0.40))
                path.closeSubpath()
            }
            .fill(.white)
            // A tassel, not a box: a rectangle under the board reads as two
            // stacked shapes rather than a mortarboard.
            Path { path in
                path.move(to: CGPoint(x: side * 0.82, y: side * 0.47))
                path.addLine(to: CGPoint(x: side * 0.82, y: side * 0.74))
            }
            .stroke(.white, style: StrokeStyle(lineWidth: side * 0.055, lineCap: .round))
            Circle()
                .fill(.white)
                .frame(width: side * 0.13, height: side * 0.13)
                .offset(x: side * 0.32, y: side * 0.29)
        }
    }

    private var flower: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { petal in
                Ellipse()
                    .fill(.white)
                    .frame(width: side * 0.27, height: side * 0.33)
                    .offset(y: -side * 0.17)
                    .rotationEffect(.degrees(Double(petal) * 72))
            }
            Circle()
                .fill(.white.opacity(0.72))
                .frame(width: side * 0.17, height: side * 0.17)
        }
    }

    private var pin: some View {
        Path { path in
            path.move(to: CGPoint(x: side * 0.50, y: side * 0.90))
            path.addCurve(to: CGPoint(x: side * 0.22, y: side * 0.40),
                          control1: CGPoint(x: side * 0.34, y: side * 0.70),
                          control2: CGPoint(x: side * 0.22, y: side * 0.55))
            path.addArc(center: CGPoint(x: side * 0.50, y: side * 0.40),
                        radius: side * 0.28,
                        startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            path.addCurve(to: CGPoint(x: side * 0.50, y: side * 0.90),
                          control1: CGPoint(x: side * 0.78, y: side * 0.55),
                          control2: CGPoint(x: side * 0.66, y: side * 0.70))
            path.closeSubpath()
        }
        .fill(.white)
        .compositingGroup()
        .overlay {
            Circle()
                .frame(width: side * 0.20, height: side * 0.20)
                .offset(y: -side * 0.10)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
    }
}
