import SwiftUI

/// The package's entry point. **The only public view.** A host mounts this and
/// needs to know nothing else — which is what makes the standalone app a
/// different `App` around the same view rather than a rewrite (P39).
public struct FarshoreRootView: View {
    @State private var terrain: Terrain?
    @State private var failed = false
    @State private var input: SIMD2<Double> = .zero
    @State private var heading: Double = 0

    /// The previous `DragGesture` translation, so each callback can turn by the
    /// **difference** rather than by the running total. See `turnGesture`.
    @State private var lastTurnTranslation: CGFloat = 0

    /// Radians of yaw per point of horizontal drag.
    ///
    /// This is a rate over *distance*, not over events, which is the whole
    /// point of the delta handling in `turnGesture`. Roughly: a full swipe
    /// across an iPhone (≈390 pt) turns you about 112°, so a look-behind is
    /// three swipes — deliberately slower than a shooter, because this is a
    /// walking game and the camera is a third-person follow, not a gun sight.
    ///
    /// The number is chosen to reproduce the *feel* of the integrating version
    /// it replaces, so the owner's device tuning is not thrown away: that code
    /// multiplied by 0.00035 on every gesture callback, and a 200 pt swipe
    /// taken over half a second at 60 Hz fired ~30 of them averaging ~100 pt
    /// of translation each, i.e. ≈1.05 rad ≈ 0.005 rad/pt. That equivalence
    /// only held at 60 Hz over half a second, which is exactly why it had to
    /// go — but it is the best estimate of what "right" felt like.
    private static let turnRadiansPerPoint: Double = 0.005

    public init() {}

    public var body: some View {
        ZStack {
            if let terrain {
                IslandSceneView(terrain: terrain, input: $input, heading: $heading)
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
    /// **`DragGesture.Value.translation` is the total offset since the drag
    /// began, not the delta since the last callback.** Subtracting it directly
    /// on every `onChanged` — which this did until the final branch review —
    /// *integrates* the drag: hold your finger still 200 pt from where you
    /// started and the world keeps spinning, one more 200 pt-worth of turn per
    /// event. The turn then scales with how *long* the drag lasted rather than
    /// how far it went (the same 200 pt swipe gave ~60° over half a second and
    /// ~240° over two), and it doubled again on a 120 Hz ProMotion display,
    /// because ProMotion delivers twice as many callbacks for the same finger
    /// movement. Any sensitivity tuned on one device was therefore wrong on
    /// the other, which is not a thing more tuning can fix.
    ///
    /// So: keep the previous translation and apply the difference. `onEnded`
    /// resets it, because the next drag's translation restarts from zero and a
    /// stale baseline would snap the heading by the whole of the last drag on
    /// the first frame of the next one.
    ///
    /// `MoveJoystick` reads `translation` raw *and is correct to*: a thumb pad
    /// wants the absolute offset from where the finger landed. Same property,
    /// opposite correct usage — which is why this needed spelling out rather
    /// than made consistent.
    private var turnGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let delta = value.translation.width - lastTurnTranslation
                lastTurnTranslation = value.translation.width
                heading -= Double(delta) * Self.turnRadiansPerPoint
            }
            .onEnded { _ in lastTurnTranslation = 0 }
    }
}
