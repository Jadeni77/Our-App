import SwiftUI

/// Going out, and coming round at the fire.
///
/// The beat matters more than the words. A death screen that appears the
/// instant a need hits zero reads as a failure dialog — the game telling you
/// off. Fading down, holding on black, and only then speaking reads as
/// *losing consciousness*, which is the thing that actually happened, and it
/// gives the player a second to work out what they did wrong before being
/// asked to do anything. That second is doing real work here: this island
/// deliberately has no meters (the owner's ruling), so the only account the
/// player ever gets of what killed them is this card.
///
/// **The one blocking control on screen while it is up.** It covers
/// everything, including `FirstTimeCard`, and it swallows the tap that
/// dismisses it rather than letting it fall through to the joystick or the
/// turn gesture underneath.
struct BlackoutView: View {
    /// Called once, on the tap. Everything the wake actually does —
    /// reviving, moving to the fire, resetting the clock — belongs to
    /// `IslandSceneView.Coordinator.wake(now:)`, which owns the driver and
    /// the clock. This view only reports the tap.
    let onContinue: () -> Void

    /// Long enough to read as passing out rather than as a cut.
    private static let fadeSeconds: Double = 1.4
    /// Black, and nothing else, before the words. The pause is the point.
    private static let holdSeconds: Double = 0.9
    private static let messageFadeSeconds: Double = 0.9

    @State private var darkness: Double = 0
    @State private var showMessage = false

    var body: some View {
        ZStack {
            Color.black
                .opacity(darkness)
                .ignoresSafeArea()

            if showMessage {
                VStack(spacing: 16) {
                    Text("farshore.death.title", bundle: .module)
                        .font(.title2.weight(.semibold))
                    Text("farshore.death.body", bundle: .module)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.85))
                    Text("farshore.death.continue", bundle: .module)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.top, 18)
                }
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(40)
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        // Hit-testable across the whole screen from the first frame, while
        // it is still fully transparent. Blocking the controls underneath
        // has to start when the blackout starts, not when it finishes
        // fading — the player is already dead, and a joystick that still
        // works for a second and a half says otherwise.
        .contentShape(Rectangle())
        .onTapGesture {
            // Ignored until the message is up, so a tap already in flight
            // when the player died cannot skip the one explanation of what
            // killed them.
            if showMessage { onContinue() }
        }
        .task { await goOut() }
    }

    private func goOut() async {
        withAnimation(.easeInOut(duration: Self.fadeSeconds)) { darkness = 1 }
        try? await Task.sleep(for: .seconds(Self.fadeSeconds + Self.holdSeconds))
        withAnimation(.easeIn(duration: Self.messageFadeSeconds)) { showMessage = true }
    }
}
