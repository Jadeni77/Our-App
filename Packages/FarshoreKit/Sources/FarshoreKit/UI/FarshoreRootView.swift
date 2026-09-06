import SwiftUI

/// The package's entry point. **The only public view.** A host mounts this and
/// needs to know nothing else — which is what makes the standalone app a
/// different `App` around the same view rather than a rewrite (P39).
public struct FarshoreRootView: View {
    @State private var terrain: Terrain?
    @State private var failed = false
    @State private var input: SIMD2<Double> = .zero
    @State private var heading: Double = 0

    public init() {}

    public var body: some View {
        ZStack {
            if let terrain {
                IslandSceneView(terrain: terrain, input: $input, heading: $heading)
                    .ignoresSafeArea()
                    .gesture(
                        DragGesture()
                            .onChanged { heading -= Double($0.translation.width) * 0.00035 }
                    )
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
}
