import SwiftUI

/// S2's arm feedback, in full: a drop target that has been hovered past the
/// arm delay swells *and* glows — the glow is what says "release joins us"
/// as opposed to the plain spread of a reorder gap. One modifier so the
/// three root tile kinds can't drift apart.
struct ArmedTargetHighlight: ViewModifier {
    let armed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(armed ? 1.12 : 1)
            .shadow(color: Theme.glow.opacity(armed ? 0.85 : 0),
                    radius: armed ? 14 : 0)
            // The state signal stays under Reduce Motion; only the spring
            // does not (same contract as Wobble).
            .animation(reduceMotion ? nil : Theme.springy, value: armed)
    }
}
