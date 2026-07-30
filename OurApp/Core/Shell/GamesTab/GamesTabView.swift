import SwiftUI

/// The springboard (P11): the platform's launcher surface. v1 of this view
/// renders the layout and launches modules; folders open in FolderOverlayView
/// and arranging arrives with the jiggle wiring.
struct GamesTabView: View {
    @Environment(GamesLayoutStore.self) private var store
    @State private var openModule: ModuleDescriptor?
    @State private var openCollectionID: UUID?
    @State private var renamingNewCollection = false
    @Namespace private var folderNamespace

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

            if let openCollectionID,
               case .collection(let collection)? = store.layout.items.first(where: {
                   $0.id == .collection(openCollectionID)
               }) {
                FolderOverlayView(
                    collection: collection,
                    store: store,
                    isEditing: false,                    // becomes jiggle.isEditing in Task 9
                    startsRenaming: renamingNewCollection,
                    onLaunch: { module in
                        self.openCollectionID = nil
                        renamingNewCollection = false
                        openModule = module
                    },
                    onClose: {
                        withAnimation(Theme.springy) { self.openCollectionID = nil }
                        renamingNewCollection = false
                    })
                .matchedGeometryEffect(id: collection.id, in: folderNamespace,
                                       isSource: false)
                .zIndex(2)
                .transition(.scale(scale: 0.3).combined(with: .opacity))
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
                .matchedGeometryEffect(id: collection.id, in: folderNamespace,
                                       isSource: openCollectionID != collection.id)
                .onTapGesture {
                    Haptics.tap()
                    withAnimation(Theme.springy) { openCollectionID = collection.id }
                }
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

#Preview("With a collection") {
    let modules = [FoodDecisionModule.descriptor] + SampleModules.descriptors
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("preview-folder.json")
    let store = GamesLayoutStore(modules: modules, fileURL: url)
    let _ = store.formCollection(target: "sample-stars", dragged: "sample-dice",
                                 named: "Play 🎲")
    GamesTabView().environment(store)
}
