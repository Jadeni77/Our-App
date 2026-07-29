import SwiftUI

/// The platform's shared design language (principle 9, decision P7).
/// One place to tune the feel — shell and modules consume these tokens.
enum Theme {
    // MARK: Palette — "dusk dream": deep indigo through rose into peach glow.
    static let indigo = Color(red: 0.16, green: 0.13, blue: 0.35)
    static let violet = Color(red: 0.35, green: 0.20, blue: 0.55)
    static let rose = Color(red: 0.85, green: 0.45, blue: 0.60)
    static let peach = Color(red: 0.98, green: 0.75, blue: 0.60)
    static let glow = Color(red: 1.00, green: 0.92, blue: 0.85)

    /// Full-bleed base gradient for shell backgrounds.
    static let duskGradient = LinearGradient(
        colors: [indigo, violet, rose, peach],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: Motion
    static let springy = Animation.spring(duration: 0.45, bounce: 0.35)
    static let gentle = Animation.easeInOut(duration: 0.8)

    // MARK: Type
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}
