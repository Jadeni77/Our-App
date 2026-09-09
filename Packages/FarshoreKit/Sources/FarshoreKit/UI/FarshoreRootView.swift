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
    /// Ticks up once per `ActionButton` tap; read by `IslandSceneView`,
    /// which forwards it into the coordinator that actually owns
    /// `SurvivalDriver`. See `IslandSceneView.takeRequest`'s doc comment for
    /// why this flows in as a plain counter rather than a `Binding<Bool>`.
    @State private var takeRequest = 0

    /// Which needs have already had their first-time card dismissed.
    /// **In-memory for this slice, deliberately** — see `FirstTimeCard`'s
    /// doc comment for why giving only this one flag a longer life than the
    /// rest of slice 2's session-scoped state would be a special case with
    /// no use before slice 3 adds persistence for everything at once.
    @State private var taughtNeeds: Set<Need> = []

    /// Holds the drag arithmetic. Lives in `TurnTracker` rather than inline in
    /// `turnGesture` so it can be tested — see the note there.
    @State private var turn = TurnTracker()

    public init() {}

    public var body: some View {
        ZStack {
            if let terrain {
                IslandSceneView(terrain: terrain, input: $input, heading: $heading,
                                survivalState: $survivalState, offer: $offer,
                                takeRequest: takeRequest)
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
                            ActionButton(offer: offer) { takeRequest += 1 }
                                .padding(.trailing, 34)
                        }
                    }
                }
                .padding(.bottom, 26)

                // Blocking, so it belongs on top of the controls above, not
                // below them. `needForFirstTimeCard` re-derives from
                // `taughtNeeds` every body evaluation rather than caching
                // "is a card showing" separately — one source of truth for
                // whether a card is due, not two that could disagree.
                if let dueNeed = NeedSignalRules.needForFirstTimeCard(state: survivalState, taught: taughtNeeds) {
                    FirstTimeCard(need: dueNeed) {
                        // Marked seen HERE, on dismissal, never on appear —
                        // see FirstTimeCard's doc comment (Moonshot M38).
                        taughtNeeds.insert(dueNeed)
                    }
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
