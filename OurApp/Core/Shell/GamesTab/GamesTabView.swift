import SwiftUI

/// The springboard (P11): the platform's launcher surface. v1 of this view
/// renders the layout and launches modules; folders open in FolderOverlayView
/// and arranging arrives with the jiggle wiring.
struct GamesTabView: View {
    @Environment(GamesLayoutStore.self) private var store
    @State private var openModule: ModuleDescriptor?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 18), count: 4)

    var body: some View {
        ZStack {
            DreamyBackground()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 22) {
                    ForEach(store.layout.items) { item in
                        tile(for: item)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
        }
        .fullScreenCover(item: $openModule) { module in
            ModuleHostView(module: module)
        }
    }

    @ViewBuilder
    private func tile(for item: GamesLayout.Item) -> some View {
        switch item {
        case .app(let moduleID):
            if let module = store.module(for: moduleID) {
                AppTileView(module: module)
                    .onTapGesture {
                        Haptics.tap()
                        openModule = module
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(Text(module.name))
            }
        case .collection(let collection):
            CollectionTileView(collection: collection, store: store)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(Text(verbatim: collection.name))
        }
    }
}

#Preview {
    GamesTabView()
        .environment(GamesLayoutStore(
            modules: [FoodDecisionModule.descriptor],
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("preview-games-tab.json")))
}
