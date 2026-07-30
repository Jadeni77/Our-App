import SwiftUI

/// The platform's mount point (P11): a themed tab bar of surfaces. Modules
/// are registered here — one line per module, nothing else crosses the seam.
struct AppShell: View {
    enum AppTab: Hashable {
        case home, games
    }

    private let modules: [ModuleDescriptor]
    @State private var store: GamesLayoutStore
    @State private var selection: AppTab

    init() {
        var modules = [
            FoodDecisionModule.descriptor,
        ]
        #if DEBUG
        modules += SampleModules.descriptors
        #endif
        self.modules = modules
        _store = State(initialValue: GamesLayoutStore(modules: modules))
        _selection = State(initialValue:
            Self.launchArguments.contains("-selectGames") ? .games : .home)
    }

    var body: some View {
        TabView(selection: $selection) {
            CouplesHomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)
            GamesTabView()
                .tabItem { Label("Games", systemImage: "gamecontroller.fill") }
                .tag(AppTab.games)
        }
        .tint(Theme.indigo)   // reads on the gradient's peach bottom, where the bar sits
        .environment(store)
    }

    private static var launchArguments: [String] {
        #if DEBUG
        ProcessInfo.processInfo.arguments
        #else
        []
        #endif
    }
}

#Preview {
    AppShell()
}
