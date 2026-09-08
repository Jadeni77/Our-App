import SwiftUI

/// The package's entry point. **The only public view.** A host mounts this and
/// needs to know nothing else — which is what makes the standalone app a
/// different `App` around the same view rather than a rewrite (P39).
public struct FarshoreRootView: View {
    @State private var terrain: Terrain?
    @State private var failed = false
    @State private var input: SIMD2<Double> = .zero
    @State private var heading: Double = 0
    /// Read by nobody yet — Task 5 only wires the driver output out of
    /// `IslandSceneView`. Task 6's `NeedsFeedback`/`ActionButton` are the
    /// consumers; until then these exist purely so the coordinator has
    /// somewhere real to push `SurvivalDriver.state`/`.offer` every frame.
    @State private var survivalState: SurvivalState = .rested
    @State private var offer: ForagePoint?

    /// Holds the drag arithmetic. Lives in `TurnTracker` rather than inline in
    /// `turnGesture` so it can be tested — see the note there.
    @State private var turn = TurnTracker()

    public init() {}

    public var body: some View {
        ZStack {
            if let terrain {
                IslandSceneView(terrain: terrain, input: $input, heading: $heading,
                                survivalState: $survivalState, offer: $offer)
                    .ignoresSafeArea()
                    .gesture(turnGesture)
                VStack {
                    Spacer()
                    HStack {
                        MoveJoystick { input = $0 }
                            .padding(.leading, 34)
                        Spacer()
                    }
                }
                .padding(.bottom, 26)
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
