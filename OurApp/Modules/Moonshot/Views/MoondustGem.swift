import SwiftUI

/// The moondust mark (M31): a four-point sparkle, code-drawn (principle 9).
/// Fill it with `Theme.glow` wherever the wallet shows — win overlay,
/// fling picker, home hub.
struct MoondustGem: Shape {
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX, cy = rect.midY
        let pinchX = rect.width * 0.12, pinchY = rect.height * 0.12
        var path = Path()
        path.move(to: CGPoint(x: cx, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: cy),
                          control: CGPoint(x: cx + pinchX, y: cy - pinchY))
        path.addQuadCurve(to: CGPoint(x: cx, y: rect.maxY),
                          control: CGPoint(x: cx + pinchX, y: cy + pinchY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: cy),
                          control: CGPoint(x: cx - pinchX, y: cy + pinchY))
        path.addQuadCurve(to: CGPoint(x: cx, y: rect.minY),
                          control: CGPoint(x: cx - pinchX, y: cy - pinchY))
        path.closeSubpath()
        return path
    }
}
