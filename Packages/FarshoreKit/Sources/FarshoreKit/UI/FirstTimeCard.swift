import SwiftUI

/// Blocks the screen the first time a need crosses
/// `SurvivalRules.criticalThreshold`, names the need, and says plainly what
/// to do about it — the one piece of teaching this island does that is not
/// left to the player to infer from a vignette.
///
/// **Marked seen on dismissal only.** `FarshoreRootView` decides *whether*
/// to show this view from `NeedSignalRules.needForFirstTimeCard`, and must
/// only add `need` to its `taught` set from `onDismiss` — never from
/// `.onAppear` on this view. This is Moonshot M38, learned the hard way
/// there: a lesson that was never actually on screen (a card that appeared
/// and was torn down by some other state change before the player read it)
/// has not been taught, and marking it taught on appear would let that
/// exact failure hide itself. The reverse also has to hold, which is why
/// the flag is not flipped optimistically the instant the card is
/// constructed: shown-but-not-dismissed is not taught either.
///
/// **In-memory for this slice, on purpose, not by oversight.** `taught`
/// lives in `FarshoreRootView`'s `@State` and is gone the moment the app
/// relaunches. Slice 2 persists nothing at all yet — not the terrain seed's
/// effects, not `SurvivalState`, not which bushes are picked — so giving
/// only this one flag a longer life than everything else on screen next to
/// it would be a special case with no use until slice 3 gives the whole
/// picture persistence at once.
struct FirstTimeCard: View {
    let need: Need
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 24) {
                Text(messageKey, bundle: .module)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                Button(action: onDismiss) {
                    Text("farshore.card.dismiss", bundle: .module)
                        .font(.headline)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(32)
        }
    }

    private var messageKey: LocalizedStringKey {
        switch need {
        case .water: return "farshore.need.water.first"
        case .food: return "farshore.need.food.first"
        case .warmth: return "farshore.need.warmth.first"
        }
    }
}
