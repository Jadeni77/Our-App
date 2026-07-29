import SwiftUI

/// The platform's mount point: the themed couples home (P4). Modules are
/// registered here — one line per module, nothing else crosses the seam.
struct AppShell: View {
    private let modules = [
        FoodDecisionModule.descriptor,
    ]

    var body: some View {
        CouplesHomeView(modules: modules)
    }
}

#Preview {
    AppShell()
}
