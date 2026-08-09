import SwiftUI

/// The shell's full-bleed art, drawn in code (original by construction — no
/// image assets): the moonlit gradient, a softly bobbing full moon, two slowly
/// drifting radial glows, and a field of drifting particles. TimelineView
/// re-renders ~30fps; all motion derives from wall-clock time so it's smooth
/// and stateless.
struct DreamyBackground: View {
    var parallax: CGSize = .zero
    /// Home's hero art. Sub-pages pass `false`: the moon sits at 20% of the
    /// screen height with a 300pt halo — positioned to clear Home's avatars and
    /// sit above its counter — which is exactly where a sub-page puts its own
    /// content, and the halo washes the text out. Same reasoning as the tilt
    /// parallax they already drop: it belongs to Home.
    var showsMoon: Bool = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Theme.duskGradient

                // Two big soft glows drifting on slow, incommensurate orbits.
                glow(color: Theme.rose.opacity(0.55), radius: 320,
                     x: 0.30 + 0.10 * sin(t / 11), y: 0.28 + 0.06 * cos(t / 13))
                    .offset(x: parallax.width, y: parallax.height)
                glow(color: Theme.peach.opacity(0.45), radius: 260,
                     x: 0.72 + 0.08 * cos(t / 9), y: 0.62 + 0.07 * sin(t / 15))
                    .offset(x: parallax.width * 1.6, y: parallax.height * 1.6)

                if showsMoon {
                    moon(t: t)
                        .offset(x: parallax.width * 1.2, y: parallax.height * 1.2)
                }

                ParticleField(time: t)
                    .offset(x: parallax.width * 0.6, y: parallax.height * 0.6)
            }
        }
        .ignoresSafeArea()
    }

    /// A full circular moon with a halo, bobbing almost imperceptibly (P8:
    /// reference-inspired structure, original code-drawn art).
    private func moon(t: TimeInterval) -> some View {
        GeometryReader { geo in
            // Top-center like the reference — clear of the corner avatars.
            let x = geo.size.width * 0.52
            let y = geo.size.height * (0.20 + 0.006 * sin(t / 7))
            ZStack {
                RadialGradient(colors: [Theme.glow.opacity(0.55), .clear],
                               center: .center, startRadius: 30, endRadius: 150)
                    .frame(width: 300, height: 300)
                Circle()
                    .fill(LinearGradient(colors: [.white, Theme.glow],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 86, height: 86)
                    .shadow(color: Theme.glow.opacity(0.9), radius: 26)
            }
            .position(x: x, y: y)
        }
        .allowsHitTesting(false)
    }

    private func glow(color: Color, radius: CGFloat, x: Double, y: Double) -> some View {
        GeometryReader { geo in
            RadialGradient(colors: [color, .clear], center: .center,
                           startRadius: 0, endRadius: radius)
                .frame(width: radius * 2, height: radius * 2)
                .position(x: geo.size.width * x, y: geo.size.height * y)
        }
    }
}

/// Drifting soft dots. Each particle's path is a pure function of (seed, time),
/// wrapping vertically — no per-frame state kept between frames.
private struct ParticleField: View {
    let time: TimeInterval
    private static let seeds: [(x: Double, speed: Double, size: Double, phase: Double)] =
        (0..<26).map { i in
            var generator = SeededGenerator(seed: UInt64(i) &* 0x9E37_79B9)
            return (
                x: Double.random(in: 0.02...0.98, using: &generator),
                speed: Double.random(in: 8...26, using: &generator),
                size: Double.random(in: 2.5...7, using: &generator),
                phase: Double.random(in: 0...1, using: &generator)
            )
        }

    var body: some View {
        Canvas { context, size in
            for seed in Self.seeds {
                let progress = (seed.phase + time / seed.speed).truncatingRemainder(dividingBy: 1)
                let y = size.height * (1.05 - progress * 1.1)
                let x = size.width * seed.x + sin(time / 4 + seed.phase * 10) * 14
                let rect = CGRect(x: x, y: y, width: seed.size, height: seed.size)
                context.opacity = 0.20 + 0.25 * sin(progress * .pi)
                context.fill(
                    Circle().path(in: rect),
                    with: .color(Theme.glow)
                )
            }
        }
        .allowsHitTesting(false)
    }
}

/// Deterministic RNG so the particle layout is stable across launches.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

#Preview {
    DreamyBackground()
}
