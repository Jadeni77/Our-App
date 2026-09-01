import SwiftUI

/// The platform's mount point (P11): a themed tab bar of surfaces. Modules
/// are registered here — one line per module, nothing else crosses the seam.
struct AppShell: View {
    enum AppTab: Hashable {
        case home, games
    }

    private static let modules: [ModuleDescriptor] = {
        var modules = [
            FoodDecisionModule.descriptor,
            MoonshotModule.descriptor,
        ]
        #if DEBUG
        modules += SampleModules.descriptors
        #endif
        return modules
    }()

    /// Once per process, not per render: the shell struct is re-inited by
    /// every App-level invalidation (a language switch, say), and the store's
    /// init does disk I/O — `@State(initialValue:)` would discard a freshly
    /// built store each time but still pay for building it (post-#14
    /// follow-up: store re-init churn).
    @MainActor private static let store = GamesLayoutStore(modules: modules)
    @MainActor private static let artwork = ArtworkStore()

    @State private var selection: AppTab
    /// Headless screenshot path (like -selectGames): mounts a module's host
    /// directly, since simctl can't tap tiles. DEBUG-only via launchArguments.
    @State private var debugModule: ModuleDescriptor?
    @State private var debugModuleMounted = false

    init() {
        _selection = State(initialValue:
            Self.launchArguments.contains("-selectGames") ? .games : .home)
    }

    var body: some View {
        TabView(selection: $selection) {
            CouplesHomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)
            GamesTabView()
                .tabItem { Label("Apps", systemImage: "square.grid.2x2.fill") }
                .tag(AppTab.games)
        }
        // **At the root, so every page is live.** Ticking only on Home left
        // every sub-page frozen at whatever had arrived before you opened it.
        .syncingWhileVisible()
        .tint(Theme.indigo)   // reads on the gradient's peach bottom, where the bar sits
        .environment(Self.store)
        .environment(Self.artwork)
        .fullScreenCover(item: $debugModule) { ModuleHostView(module: $0) }
        .onAppear {
            // Presenting a cover during app startup races UIKit's rotation
            // machinery (window stays portrait while the status bar turns) —
            // the tile-tap path never launches this early. Mimic it: mount
            // the debug module after the shell settles. One-shot: dismissing
            // the cover re-fires onAppear, and Close must not revolve.
            guard Self.launchArguments.contains("-moonshot"), !debugModuleMounted else { return }
            debugModuleMounted = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                debugModule = MoonshotModule.descriptor
            }
        }
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
