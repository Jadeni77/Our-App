import SwiftUI

/// Tells the player what the island is doing to them without a single
/// meter, ring, or number on screen. Four rounds of mockups tried the
/// obvious "bar for each need" and the owner rejected all of them,
/// repeatedly, for something that reads as the real world instead of as UI
/// — so the needs speak through the screen itself:
///
/// - **Thirst** — a dry, warm vignette creeping in from the edges.
/// - **Cold** — desaturation plus a slow breathing-fog pulse.
/// - **Hunger** — a slow darkening at the periphery, weaker than thirst's.
///
/// Every effect's strength comes from `NeedSignalRules.intensity`, so "when
/// does anything appear" is one tested function, not three copies of the
/// same threshold arithmetic living in view code no test can reach.
///
/// `allowsHitTesting(false)`: this view exists to be looked at, never
/// touched — it must never steal a drag meant for the look/turn gesture or
/// a tap meant for `ActionButton`.
struct NeedsFeedback: View {
    let state: SurvivalState

    /// Drives the cold breathing-fog pulse. Animated once, via `onAppear`
    /// and `repeatForever`, rather than by a per-frame timer of our own —
    /// Core Animation interpolates it without this view's `body` having to
    /// be re-invoked at display-refresh rate on top of the ~30 Hz
    /// `SurvivalState` already drives (see the task report's performance
    /// note).
    @State private var breathe = false

    /// Fixed value types, built once per process rather than reallocated on
    /// every ~30 Hz `body` re-evaluation. Only `opacity` below changes per
    /// frame; the gradients themselves — their color stops — never do, so
    /// there is nothing here for a change in `state` to reallocate.
    private static let thirstGradient = Gradient(colors: [
        .clear, Color(red: 0.55, green: 0.32, blue: 0.12).opacity(0.85)
    ])
    private static let hungerGradient = Gradient(colors: [.clear, .black.opacity(0.85)])
    private static let breathGradient = Gradient(colors: [.white.opacity(0.55), .clear])

    private var thirst: Double { NeedSignalRules.intensity(state.water) }
    private var cold: Double { NeedSignalRules.intensity(state.warmth) }
    private var hunger: Double { NeedSignalRules.intensity(state.food) }

    var body: some View {
        ZStack {
            hungerVignette
            thirstVignette
            coldDesaturation
            coldBreath
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        // A long ease so nothing on screen snaps — the owner's own words for
        // why bars and rings were rejected apply just as much to a jump cut.
        .animation(.easeInOut(duration: 2.5), value: state)
        .onAppear {
            withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }

    private var thirstVignette: some View {
        RadialGradient(gradient: Self.thirstGradient, center: .center,
                       startRadius: 40, endRadius: 420)
            .opacity(thirst)
    }

    private var hungerVignette: some View {
        RadialGradient(gradient: Self.hungerGradient, center: .center,
                       startRadius: 60, endRadius: 460)
            .opacity(hunger * NeedSignalRules.hungerStrengthRelativeToThirst)
    }

    /// A flat gray wash blended by saturation rather than drawn as its own
    /// visible layer — `.saturation` reads the composited result *beneath*
    /// it in this same `ZStack`, which is what lets an overlay desaturate
    /// the 3D scene under it without `NeedsFeedback` ever touching
    /// `IslandSceneView`.
    private var coldDesaturation: some View {
        Color(white: 0.5)
            .blendMode(.saturation)
            .opacity(cold)
    }

    private var coldBreath: some View {
        RadialGradient(gradient: Self.breathGradient, center: .bottom,
                       startRadius: 10, endRadius: 260)
            .opacity(cold * (breathe ? 0.5 : 0.15))
    }
}
