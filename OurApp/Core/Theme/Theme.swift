import SwiftUI

/// The platform's shared design language (principle 9, decision P7).
/// One place to tune the feel — shell and modules consume these tokens.
enum Theme {
    // MARK: Palette — "moonlit dream": brightened 2026-07-29 (P8) from the
    // original deep dusk to a softer periwinkle-through-blush sky.
    static let indigo = Color(red: 0.44, green: 0.45, blue: 0.72)
    static let violet = Color(red: 0.62, green: 0.55, blue: 0.83)
    static let rose = Color(red: 0.93, green: 0.66, blue: 0.77)
    static let peach = Color(red: 0.99, green: 0.86, blue: 0.78)
    static let glow = Color(red: 1.00, green: 0.95, blue: 0.88)

    /// Full-bleed base gradient for shell backgrounds.
    static let duskGradient = LinearGradient(
        colors: [indigo, violet, rose, peach],
        startPoint: .top,
        endPoint: .bottom
    )

    /// The dimming layer behind overlays (folder zoom, future sheets) — one
    /// token so every scrim darkens the dream by the same amount.
    static let scrim = Color.black.opacity(0.35)

    // MARK: Motion
    static let springy = Animation.spring(duration: 0.45, bounce: 0.35)

    // MARK: Type
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}
