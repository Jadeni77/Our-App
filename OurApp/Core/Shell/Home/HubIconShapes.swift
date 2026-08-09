import SwiftUI

/// Primitives the hub glyphs are built from. Each draws into its own `rect`, so
/// the caller sizes it and the shape scales — no fixed points anywhere.

/// A rounded heart: two lobes meeting at a point.
///
/// Expects a frame of roughly **w/h 1.05–1.2** (both callers sit at ~1.1). The
/// lobe radius scales off the width while its centre scales off the height, so
/// a much wider frame lifts the lobes above y = 0 — and shapes aren't clipped
/// to their frame, so it would bleed rather than fail visibly.
struct HeartShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width, height = rect.height
        var path = Path()
        path.move(to: CGPoint(x: width * 0.5, y: height))
        path.addCurve(to: CGPoint(x: 0, y: height * 0.30),
                      control1: CGPoint(x: width * 0.14, y: height * 0.76),
                      control2: CGPoint(x: 0, y: height * 0.54))
        path.addArc(center: CGPoint(x: width * 0.25, y: height * 0.30),
                    radius: width * 0.25,
                    startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addArc(center: CGPoint(x: width * 0.75, y: height * 0.30),
                    radius: width * 0.25,
                    startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addCurve(to: CGPoint(x: width * 0.5, y: height),
                      control1: CGPoint(x: width, y: height * 0.54),
                      control2: CGPoint(x: width * 0.86, y: height * 0.76))
        path.closeSubpath()
        return path
    }
}

/// A speech bubble: rounded body with a tail off the lower-leading corner.
///
/// The tail is deliberately stubby and only slightly slanted. A long, steeply
/// angled one renders as a detached sliver at tile size — it stops reading as
/// speech and starts reading as a paper dart.
struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width, height = rect.height
        let bodyHeight = height * 0.78
        let cornerRadius = bodyHeight * 0.26
        var path = Path(roundedRect: CGRect(x: 0, y: 0, width: width, height: bodyHeight),
                        cornerRadius: cornerRadius, style: .continuous)
        // The base must sit on genuinely flat bottom edge. A `.continuous`
        // corner keeps curving to roughly 1.5× its radius along the edge, so a
        // base placed at the radius still overhangs the curve and the tail
        // renders with a step cut out of it. It also starts just inside the
        // body vertically, so the two shapes fuse rather than abut.
        // Two things this geometry gets wrong if you're careless, both of which
        // look like a rendering bug rather than a design choice:
        //
        // 1. The apex must sit *between* the base points. Outside them, the
        //    triangle reads as a slanted dart or a flag on a pole, not speech.
        // 2. The winding must match the rounded rect's. Under nonzero fill an
        //    opposite-wound subpath *cancels* where the two overlap, cutting a
        //    notch along the seam — so the tail must be traced right-to-left,
        //    the same direction `Path(roundedRect:)` traces.
        let baseY = bodyHeight * 0.93
        path.move(to: CGPoint(x: width * 0.50, y: baseY))
        path.addLine(to: CGPoint(x: width * 0.34, y: height))
        path.addLine(to: CGPoint(x: width * 0.28, y: baseY))
        path.closeSubpath()
        return path
    }
}

/// The question mark's stroke — an over-arc falling into a hook. Stroked by the
/// caller with a round cap; the dot beneath is a separate circle.
struct QuestionMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width, height = rect.height
        var path = Path()
        path.move(to: CGPoint(x: width * 0.14, y: height * 0.32))
        path.addQuadCurve(to: CGPoint(x: width * 0.86, y: height * 0.34),
                          control: CGPoint(x: width * 0.5, y: height * -0.20))
        path.addQuadCurve(to: CGPoint(x: width * 0.5, y: height * 0.70),
                          control: CGPoint(x: width * 0.86, y: height * 0.58))
        return path
    }
}

/// A four-point sparkle with concave sides — the same star the background's
/// particles imply, drawn solid.
struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width, height = rect.height
        var path = Path()
        path.move(to: CGPoint(x: width * 0.5, y: 0))
        path.addQuadCurve(to: CGPoint(x: width, y: height * 0.5),
                          control: CGPoint(x: width * 0.58, y: height * 0.42))
        path.addQuadCurve(to: CGPoint(x: width * 0.5, y: height),
                          control: CGPoint(x: width * 0.58, y: height * 0.58))
        path.addQuadCurve(to: CGPoint(x: 0, y: height * 0.5),
                          control: CGPoint(x: width * 0.42, y: height * 0.58))
        path.addQuadCurve(to: CGPoint(x: width * 0.5, y: 0),
                          control: CGPoint(x: width * 0.42, y: height * 0.42))
        path.closeSubpath()
        return path
    }
}

#Preview {
    HStack(spacing: 20) {
        HeartShape().fill(.white).frame(width: 44, height: 40)
        BubbleShape().fill(.white).frame(width: 48, height: 44)
        QuestionMarkShape().stroke(.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            .frame(width: 32, height: 34)
        SparkleShape().fill(.white).frame(width: 30, height: 30)
    }
    .padding(30)
    .background(Theme.duskGradient)
}
