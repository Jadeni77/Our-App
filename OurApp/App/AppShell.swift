import SwiftUI

/// The platform's module mount point. Today it mounts the only module directly;
/// when module #2 arrives this becomes a switcher (TabView or similar).
struct AppShell: View {
    var body: some View {
        FoodDecisionModuleView()
    }
}

#Preview {
    AppShell()
}
