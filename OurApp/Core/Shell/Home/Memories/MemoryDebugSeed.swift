#if DEBUG
import CoreGraphics
import Foundation
import SwiftData
import UIKit

/// Headless screenshot verification can't tap a `PhotosPicker`, so
/// `-seedMemories` writes a few moments with generated pictures. One of them is
/// deliberately undated: the "Sometime" heading is otherwise unreachable
/// without a device pass, and an unphotographable state is an unverifiable one.
///
/// DEBUG only, and it declines when the timeline already holds anything, so it
/// can never sit on top of real memories.
enum MemoryDebugSeed {
    @MainActor
    static func runIfRequested(in container: ModelContainer,
                               identity: CoupleIdentityStore) {
        guard ProcessInfo.processInfo.arguments.contains("-seedMemories") else { return }

        let context = ModelContext(container)
        guard (try? context.fetchCount(FetchDescriptor<Memory>())) == 0 else { return }
        let store = MemoryPhotoStore()
        let calendar = Calendar.current
        // The third has no day — that is the whole point of the seed.
        let seeds: [(note: String, daysAgo: Int?, colours: [UIColor])] = [
            ("Kyoto, first morning", 3, [.systemPink, .systemOrange]),
            ("The long way home", 20, [.systemTeal]),
            ("no idea when this was", nil, [.systemIndigo, .systemPurple, .systemBlue]),
        ]
        var index = 0
        for seed in seeds {
            let ids = seed.colours.compactMap { colour -> String? in
                defer { index += 1 }
                return try? store.save(picture(index: index, colours: [colour]))
            }
            guard !ids.isEmpty else { continue }
            let day = seed.daysAgo.flatMap {
                calendar.date(byAdding: .day, value: -$0, to: .now)
            }
            context.insert(Memory(note: seed.note, day: day,
                                  authorID: identity.authorID, photoIDs: ids))
        }
        try? context.save()
    }

    /// Renders a `600×600` placeholder with texture at several spatial
    /// frequencies, seeded from `index` so the same call always draws the
    /// same picture — screenshots taken today have to match the ones taken
    /// next month.
    ///
    /// A flat colour fill (what this drew before) is actively misleading: a
    /// review caught `AlbumDetailView`'s hero upscaling a 400px thumbnail
    /// roughly 3x onto a full-width surface, and a flat square has no detail
    /// for that upscaling to blur — the defect was invisible in every
    /// screenshot taken against it. A gradient, several overlapping
    /// translucent shapes at different scales, and fine dot noise give the
    /// eye low, mid and high frequency detail to lose, so blur, upscaling and
    /// JPEG compression all show up the way they would on an actual photo.
    ///
    /// Not `private` — `AlbumDebugSeed` shares this rather than growing a
    /// second copy of the same generator for the same reason.
    static func picture(index: Int, colours: [UIColor]) -> Data {
        var rng = SeededGenerator(seed: index)
        let size = CGSize(width: 600, height: 600)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let base = colours.isEmpty ? [UIColor.systemBlue] : colours

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let colourSpace = CGColorSpaceCreateDeviceRGB()
            let stops = gradientStops(from: base)

            // Low frequency: the base gradient, diagonal or radial depending
            // on the seed so a whole album's covers aren't all the same
            // shape. `CGGradient` init is technically failable; a flat fill
            // of the first stop is the fallback, not skipping straight to
            // the shapes below over an untinted white background.
            if let gradient = CGGradient(colorsSpace: colourSpace, colors: stops as CFArray,
                                         locations: nil) {
                if index % 2 == 0 {
                    cg.drawLinearGradient(gradient, start: .zero,
                                          end: CGPoint(x: size.width, y: size.height), options: [])
                } else {
                    // No options paints nothing past `endRadius`, so the
                    // context's blank white stayed in all four corners of an
                    // otherwise circular gradient — a sample tile that reads
                    // as "layout bug" the moment anyone notices the white
                    // square behind the coloured circle. A real photo has no
                    // such gap; this one shouldn't either.
                    // `.drawsBeforeStartLocation` is skipped: every centre
                    // here is the square's own centre, never off-canvas, so
                    // there's nothing before the start location to fill.
                    let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                    cg.drawRadialGradient(gradient, startCenter: centre, startRadius: 0,
                                          endCenter: centre, endRadius: size.width / 2,
                                          options: [.drawsAfterEndLocation])
                }
            } else {
                base[0].setFill()
                cg.fill(CGRect(origin: .zero, size: size))
            }

            // Mid frequency: a handful of overlapping translucent shapes at
            // varying scale, like the blown-out shapes a real photo's bokeh
            // or highlights leave behind.
            for _ in 0..<Int.random(in: 5...8, using: &rng) {
                let radius = CGFloat.random(in: 40...220, using: &rng)
                let centre = CGPoint(x: CGFloat.random(in: 0...size.width, using: &rng),
                                     y: CGFloat.random(in: 0...size.height, using: &rng))
                let shade = base.randomElement(using: &rng) ?? .white
                shade.withAlphaComponent(CGFloat.random(in: 0.08...0.28, using: &rng)).setFill()
                cg.fillEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                                          width: radius * 2, height: radius * 2))
            }

            // High frequency: thin lines and fine dot noise — the detail a
            // 3x upscale turns to mush and a flat fill never had to lose.
            cg.setLineWidth(1)
            for _ in 0..<12 {
                let y = CGFloat.random(in: 0...size.height, using: &rng)
                UIColor.white.withAlphaComponent(CGFloat.random(in: 0.10...0.22, using: &rng)).setStroke()
                cg.move(to: CGPoint(x: 0, y: y))
                cg.addLine(to: CGPoint(x: size.width, y: y + CGFloat.random(in: -40...40, using: &rng)))
                cg.strokePath()
            }
            for _ in 0..<160 {
                let dot = CGFloat.random(in: 0.6...2.2, using: &rng)
                let origin = CGPoint(x: CGFloat.random(in: 0...size.width, using: &rng),
                                     y: CGFloat.random(in: 0...size.height, using: &rng))
                UIColor.white.withAlphaComponent(CGFloat.random(in: 0.05...0.35, using: &rng)).setFill()
                cg.fillEllipse(in: CGRect(origin: origin, size: CGSize(width: dot, height: dot)))
            }
        }.jpegData(compressionQuality: 0.9)!
    }

    /// At least two gradient stops, always. A single colour synthesizes its
    /// own second stop (hue nudged, brightened) rather than drawing flat —
    /// exactly the flat-fill mistake this whole function exists to undo.
    private static func gradientStops(from colours: [UIColor]) -> [CGColor] {
        guard let first = colours.first else {
            return [UIColor.systemBlue.cgColor, UIColor.systemIndigo.cgColor]
        }
        guard colours.count == 1 else { return colours.map(\.cgColor) + [colours[0].cgColor] }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        first.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let second = UIColor(hue: (hue + 0.06).truncatingRemainder(dividingBy: 1),
                             saturation: saturation, brightness: min(brightness * 1.35, 1),
                             alpha: alpha)
        return [first.cgColor, second.cgColor]
    }
}

/// A tiny seeded PRNG (SplitMix64) so a generated picture is reproducible —
/// `Int.random(in:using:)` and friends need a `RandomNumberGenerator`, and
/// the system one is deliberately unseedable, which is exactly the property
/// a screenshot fixture can't have.
///
/// `private`, like `DreamyBackground`'s own generator of the same name and
/// same shape — each file's is a private implementation detail of that
/// file's texture, not a shared utility worth extracting for two callers.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: Int) {
        state = UInt64(bitPattern: Int64(seed)) &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
#endif
