import SwiftUI

/// Module entry point (module contract: the one view the shell mounts).
struct FoodDecisionModuleView: View {
    @State private var flow = FoodDecisionFlow()

    var body: some View {
        NavigationStack {
            Group {
                switch flow.phase {
                case .propose:
                    ProposeView(flow: flow)
                case .deciding(let cuisine):
                    DecideView(flow: flow, cuisine: cuisine)
                case .decided(let cuisine):
                    DecidedView(flow: flow, cuisine: cuisine)
                }
            }
            .animation(.spring(duration: 0.35), value: flow.phase)
        }
    }
}

#Preview {
    FoodDecisionModuleView()
}
