import SwiftUI

/// The package's entry point. **The only public view.** A host mounts this and
/// needs to know nothing else — which is what makes the standalone app a
/// different `App` around the same view rather than a rewrite (P39).
public struct FarshoreRootView: View {
    @State private var terrain: Terrain?
    @State private var failed = false
    @State private var input: SIMD2<Double> = .zero
    @State private var heading: Double = 0
    /// Pushed out of the coordinator every frame (~30 Hz) and read by
    /// `NeedsFeedback`/`ActionButton`/`FirstTimeCard` below — see the task
    /// report for what keeps that render-loop rate cheap once real view
    /// content sits behind it.
    @State private var survivalState: SurvivalState = .rested
    @State private var offer: ForagePoint?
    /// Records each `ActionButton` tap **together with what was in reach
    /// when it happened**; read by `IslandSceneView`, which forwards it
    /// into the coordinator that actually owns `SurvivalDriver`. See
    /// `IslandSceneView.TakeRequest` for why the point travels with the
    /// tap rather than being looked up when the tap is handled.
    @State private var takeRequest = IslandSceneView.TakeRequest()

    /// Which needs have already had their first-time card dismissed.
    /// **In-memory for this slice, deliberately** — see `FirstTimeCard`'s
    /// doc comment for why giving only this one flag a longer life than the
    /// rest of slice 2's session-scoped state would be a special case with
    /// no use before slice 3 adds persistence for everything at once.
    @State private var taughtNeeds: Set<Need> = []

    /// The need whose card is on screen right now, **latched**.
    ///
    /// `survivalState` arrives ~30 times a second, so deriving this inside
    /// `body` meant re-answering "which need is due" on every frame the
    /// card was up. A second need crossing critical to a lower value while
    /// the player was reading would swap the text under them mid-sentence
    /// and then credit their dismissal to the need they never read about —
    /// M38 technically satisfied, the player still misled. Latching means
    /// the card that appears is the card that gets dismissed; the other
    /// need is still critical afterwards and gets its own card next.
    @State private var cardNeed: Need?

    /// Ticks up when the player taps through the blackout. Handled by the
    /// coordinator, which owns the driver and the clock — see
    /// `IslandSceneView.Coordinator.wake(now:)`.
    @State private var wakeRequest = 0

    /// Holds the drag arithmetic. Lives in `TurnTracker` rather than inline in
    /// `turnGesture` so it can be tested — see the note there.
    @State private var turn = TurnTracker()

    public init() {}

    public var body: some View {
        ZStack {
            if let terrain {
                IslandSceneView(terrain: terrain, input: $input, heading: $heading,
                                survivalState: $survivalState, offer: $offer,
                                takeRequest: takeRequest, wakeRequest: wakeRequest)
                    .ignoresSafeArea()
                    .gesture(turnGesture)

                // Purely visual, hit-tests nothing — see its own doc
                // comment for why it is safe to sit above the scene and
                // below the controls in this stack.
                NeedsFeedback(state: survivalState)

                VStack {
                    Spacer()
                    HStack {
                        MoveJoystick { input = $0 }
                            .padding(.leading, 34)
                        Spacer()
                        if let offer {
                            // The offer the player is LOOKING at goes with
                            // the tap. Anything else and the button's label
                            // and its effect can disagree — see
                            // `IslandSceneView.TakeRequest`.
                            ActionButton(offer: offer) { takeRequest.tap(offer) }
                                .padding(.trailing, 34)
                        }
                    }
                }
                .padding(.bottom, 26)

                // Blocking, so it belongs on top of the controls above, not
                // below them. Reads the latch rather than re-deriving —
                // see `cardNeed`.
                if let cardNeed {
                    FirstTimeCard(need: cardNeed) {
                        // Marked seen HERE, on dismissal, never on appear —
                        // see FirstTimeCard's doc comment (Moonshot M38).
                        taughtNeeds.insert(cardNeed)
                        self.cardNeed = nil
                    }
                }

                // Above everything, including the card: while you are out,
                // nothing else on this screen is true or usable. The state
                // it reads is pushed from the render loop, so the blackout
                // clears one frame after `wake` revives the driver rather
                // than the instant the tap lands.
                if survivalState.isDead {
                    BlackoutView { wakeRequest += 1 }
                }
            } else if failed {
                // Fail soft, never a dead end (principle 7).
                Text("farshore.load.failed", bundle: .module)
                    .foregroundStyle(.white)
            } else {
                Text("farshore.loading", bundle: .module)
                    .foregroundStyle(.white)
            }
        }
        .background(.black)
        // Arms the latch, and only ever when nothing is already latched —
        // `cardNeed == nil` is what makes it a latch rather than a rename
        // of the per-frame derivation it replaced.
        // Never while dead: every need is at or near zero when you go out,
        // so a card armed here would be waiting behind the blackout and
        // would surface after waking, telling a player who is `.rested`
        // that their mouth is dry. A lesson nobody can see is not taught
        // (M38), and one that arrives after it stopped being true is worse
        // than none. A card already on screen when you die is left alone —
        // that one is about the thing that just killed you.
        .onChange(of: survivalState) { _, state in
            guard cardNeed == nil, !state.isDead else { return }
            cardNeed = NeedSignalRules.needForFirstTimeCard(state: state, taught: taughtNeeds)
        }
        .task {
            guard terrain == nil else { return }
            do {
                let field = try HeightFieldLoader.load(.farshore01, from: .module)
                terrain = Terrain(field: field, definition: .farshore01)
            } catch {
                failed = true
            }
        }
    }

    /// Look/turn: drag anywhere on the world to swing the heading.
    ///
    /// The arithmetic is in `TurnTracker`, which documents *why* this cannot
    /// just subtract `value.translation.width`: that is the total offset since
    /// the drag began, not the delta since the last callback, so using it
    /// directly integrates the drag and makes the turn depend on the drag's
    /// duration and the display's refresh rate rather than on how far the
    /// finger moved.
    ///
    /// `MoveJoystick` reads `translation` raw *and is correct to*: a thumb pad
    /// wants the absolute offset from where the finger landed. Same property,
    /// opposite correct usage — which is why this needed spelling out rather
    /// than being made consistent.
    private var turnGesture: some Gesture {
        DragGesture()
            .onChanged { heading += turn.headingChange(translation: $0.translation.width) }
            .onEnded { _ in turn.end() }
    }
}
