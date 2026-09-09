import SwiftUI

/// The one control that turns "there is a spring in reach" into "you drank
/// from it." `FarshoreRootView` only shows this when `SurvivalDriver.offer`
/// is non-nil, so appearing/disappearing is SwiftUI's normal optional
/// idiom — this view carries no visibility state of its own.
///
/// Its tap does not assume it worked. `action` only asks the caller to try;
/// `SurvivalDriver.take` is the sole authority on whether anything actually
/// happened (Moonshot M45, documented on `take` itself) — this button would
/// otherwise repeat the exact mistake that cost days on game #1: a tap that
/// looked like success whether or not it was.
///
/// Visual idiom matches `MoveJoystick` on purpose rather than inventing a
/// second control language: an `.ultraThinMaterial` disc, plain, one
/// thumb-reachable tap, no chrome beyond what a real button would have.
struct ActionButton: View {
    let offer: ForagePoint
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(.ultraThinMaterial).frame(width: 84, height: 84)
                Text(labelKey, bundle: .module)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
        }
        .accessibilityLabel(Text(labelKey, bundle: .module))
    }

    /// `offer.action` — not `offer.need` — decides the label. `need` would
    /// need a third, unreachable case for `.warmth` (no `ForagePoint` ever
    /// carries it); `action` is exhaustive over the two verbs that actually
    /// exist, which is exactly what `ForageField.swift` documents as the
    /// reason it exists.
    private var labelKey: LocalizedStringKey {
        switch offer.action {
        case .drink: return "farshore.action.drink"
        case .eat: return "farshore.action.eat"
        }
    }
}
