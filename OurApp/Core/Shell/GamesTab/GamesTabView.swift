import SwiftUI

/// The springboard (P11): the platform's launcher surface. Renders the tile
/// grid and folder overlay (FolderOverlayView), drives full jiggle-mode
/// arranging, and launches modules full-screen.
struct GamesTabView: View {
    @Environment(GamesLayoutStore.self) private var store
    @Environment(ArtworkStore.self) private var artwork
    @State private var openModule: ModuleDescriptor?
    @State private var openCollectionID: UUID?
    @State private var renamingNewCollection = false
    @State private var addingExternalApp = false
    @State private var jiggle = JiggleController()
    @State private var tileFrames: [GamesLayout.ItemID: CGRect] = [:]
    @State private var dragLocation: CGPoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var folderNamespace

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 18), count: 4)

    var body: some View {
        ZStack {
            DreamyBackground()
                .onTapGesture {
                    if jiggle.isEditing {
                        exitEditing()
                    }
                }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 22) {
                    ForEach(displayedItems) { item in
                        tile(for: item)
                    }
                }
                .animation(Theme.springy, value: displayedItems.map(\.id))
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
                    isEditing: jiggle.isEditing,
                    startsRenaming: renamingNewCollection,
                    onBeginEditing: {
                        withAnimation(Theme.springy) { jiggle.isEditing = true }
                    },
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

            if let draggedID = jiggle.draggedItem, let location = dragLocation {
                ghost(for: draggedID)
                    .frame(width: 80)
                    .scaleEffect(1.08)
                    .position(location)
                    .allowsHitTesting(false)
                    .zIndex(3)
            }
        }
        .coordinateSpace(name: "springboard")
        .overlay(alignment: .topTrailing) {
            if jiggle.isEditing {
                Button {
                    exitEditing()
                } label: {
                    Text("Done")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                }
                .glassCard(cornerRadius: 18)
                .padding(.trailing, 16)
            }
        }
        .overlay(alignment: .topLeading) {
            // Opposite Done: add a real installed game to the springboard (S7).
            if jiggle.isEditing {
                Button {
                    Haptics.tap()
                    addingExternalApp = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 36)
                }
                .glassCard(cornerRadius: 18)
                .padding(.leading, 16)
                .accessibilityLabel(Text("Add a game"))
            }
        }
        .sheet(isPresented: $addingExternalApp) {
            AddExternalAppSheet(onCommit: commitNewExternalApp)
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-jiggleMode") {
                jiggle.isEditing = true
            }
            #endif
        }
        .fullScreenCover(item: $openModule) { module in
            ModuleHostView(module: module)
        }
    }

    /// Done and background-tap both leave edit mode this way: haptic, spring
    /// back to rest, and drop any in-flight drag so a cancelled gesture
    /// (notification shade, app switcher, backgrounding) can't strand a ghost
    /// or leave `jiggle.draggedItem` set for the next drag to inherit.
    private func exitEditing() {
        Haptics.tap()
        withAnimation(Theme.springy) { jiggle.isEditing = false }
        dragLocation = nil
        _ = jiggle.endDrag()
    }

    @ViewBuilder
    private func tile(for item: GamesLayout.Item) -> some View {
        switch item {
        case .app(let moduleID):
            if let module = store.module(for: moduleID) {
                AppTileView(module: module)
                    .modifier(Wobble(active: jiggle.isEditing, reduceMotion: reduceMotion))
                    .onTapGesture {
                        guard !jiggle.isEditing else { return }
                        Haptics.tap()
                        openModule = module
                    }
                    .onLongPressGesture(minimumDuration: 0.5) {
                        guard !jiggle.isEditing else { return }
                        Haptics.tap()
                        withAnimation(Theme.springy) { jiggle.isEditing = true }
                    }
                    .gesture(jiggle.isEditing ? dragGesture(for: item.id) : nil)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named("springboard"))
                    } action: { tileFrames[item.id] = $0 }
                    .opacity(jiggle.draggedItem == item.id ? 0.001 : 1)
                    .scaleEffect(jiggle.intent == .armedTarget(item.id) ? 1.12 : 1)
                    .animation(Theme.springy, value: jiggle.intent == .armedTarget(item.id))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(Text(module.name))
            }
        case .external(let externalID):
            if let external = store.externalApp(id: externalID) {
                ExternalTileView(app: external)
                    .modifier(Wobble(active: jiggle.isEditing, reduceMotion: reduceMotion))
                    // Launching arrives with the S7 launch path; arranging
                    // works exactly like a module tile already.
                    .onLongPressGesture(minimumDuration: 0.5) {
                        guard !jiggle.isEditing else { return }
                        Haptics.tap()
                        withAnimation(Theme.springy) { jiggle.isEditing = true }
                    }
                    .gesture(jiggle.isEditing ? dragGesture(for: item.id) : nil)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named("springboard"))
                    } action: { tileFrames[item.id] = $0 }
                    .opacity(jiggle.draggedItem == item.id ? 0.001 : 1)
                    .scaleEffect(jiggle.intent == .armedTarget(item.id) ? 1.12 : 1)
                    .animation(Theme.springy, value: jiggle.intent == .armedTarget(item.id))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(Text(verbatim: external.name))
            }
        case .collection(let collection):
            CollectionTileView(collection: collection, store: store)
                .modifier(Wobble(active: jiggle.isEditing, reduceMotion: reduceMotion))
                .matchedGeometryEffect(id: collection.id, in: folderNamespace,
                                       isSource: openCollectionID != collection.id)
                .onTapGesture {
                    Haptics.tap()
                    withAnimation(Theme.springy) { openCollectionID = collection.id }
                }
                .onLongPressGesture(minimumDuration: 0.5) {
                    guard !jiggle.isEditing else { return }
                    Haptics.tap()
                    withAnimation(Theme.springy) { jiggle.isEditing = true }
                }
                .gesture(jiggle.isEditing ? dragGesture(for: item.id) : nil)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named("springboard"))
                } action: { tileFrames[item.id] = $0 }
                .opacity(jiggle.draggedItem == item.id ? 0.001 : 1)
                .scaleEffect(jiggle.intent == .armedTarget(item.id) ? 1.12 : 1)
                .animation(Theme.springy, value: jiggle.intent == .armedTarget(item.id))
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(Text(verbatim: collection.name))
        }
    }

    private func dragGesture(for id: GamesLayout.ItemID) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("springboard"))
            .onChanged { value in
                // Keyed on identity, not nil: a cancelled drag (notification
                // shade, app switcher, backgrounding) never fires `onEnded`,
                // so `draggedItem` can be left stale — this still recognizes
                // a genuinely new drag and re-arms cleanly instead of letting
                // the next gesture inherit the wrong item's intent.
                if jiggle.draggedItem != id {
                    Haptics.tap()
                    jiggle.beginDrag(id)
                }
                dragLocation = value.location
                jiggle.updateDrag(location: value.location, frames: tileFrames,
                                  order: store.layout.items.map(\.id), now: Date())
            }
            .onEnded { value in
                let intent = jiggle.endDrag()
                dragLocation = nil
                handleRootDrop(of: id, at: value.location, intent: intent)
            }
    }

    @ViewBuilder
    private func ghost(for id: GamesLayout.ItemID) -> some View {
        switch id {
        case .app(let moduleID):
            if let module = store.module(for: moduleID) { AppTileView(module: module) }
        case .external(let externalID):
            if let external = store.externalApp(id: externalID) {
                ExternalTileView(app: external)
            }
        case .collection(let collectionID):
            if case .collection(let collection)? = store.layout.items.first(where: {
                $0.id == .collection(collectionID)
            }) {
                CollectionTileView(collection: collection, store: store)
            }
        }
    }

    /// Renders the grid from a preview order while a reorder drag is live, so
    /// neighbors spring apart to open a gap ahead of `release`.
    private var displayedItems: [GamesLayout.Item] {
        guard let dragged = jiggle.draggedItem,
              case .reorder(let insertAt) = jiggle.intent,
              let draggedItem = store.layout.items.first(where: { $0.id == dragged })
        else { return store.layout.items }
        var others = store.layout.items.filter { $0.id != dragged }
        others.insert(draggedItem, at: min(insertAt, others.count))
        return others
    }

    private func handleRootDrop(of id: GamesLayout.ItemID, at location: CGPoint,
                                intent: DropIntent) {
        switch intent {
        case .reorder(let insertAt):
            withAnimation(Theme.springy) { store.moveItem(id: id, toIndex: insertAt) }
            Haptics.tap()
        case .armedTarget(let targetID):
            guard let draggedMember = memberKey(for: id) else { return }
            switch targetID {
            case .app, .external:
                guard let targetMember = memberKey(for: targetID) else { return }
                let name = String(localized: "New collection")
                if let newID = store.formCollection(target: targetMember,
                                                    dragged: draggedMember,
                                                    named: name) {
                    Haptics.success()
                    renamingNewCollection = true
                    withAnimation(Theme.springy) { openCollectionID = newID }
                }
            case .collection(let collectionID):
                withAnimation(Theme.springy) {
                    store.addToCollection(collectionID, member: draggedMember)
                }
                Haptics.success()
            }
        case .target(let targetID):
            // Hovered but never armed: land beside the target instead.
            let others = store.layout.items.map(\.id).filter { $0 != id }
            if let index = others.firstIndex(of: targetID) {
                withAnimation(Theme.springy) { store.moveItem(id: id, toIndex: index) }
            }
            Haptics.tap()
        case .none:
            break
        }
    }

    /// The member key a root tile contributes to a collection: module id for
    /// module tiles, UUID string for externals, nothing for collections.
    private func memberKey(for id: GamesLayout.ItemID) -> String? {
        switch id {
        case .app(let moduleID): moduleID
        case .external(let externalID): externalID.uuidString
        case .collection: nil
        }
    }

    // MARK: - External apps (S7)

    private func commitNewExternalApp(_ app: GamesLayout.ExternalApp) {
        store.addExternalApp(app)
        enrich(app)
    }

    /// Fire-and-forget iTunes enrichment: official artwork + App Store page
    /// by name. Every step fails soft — the tile keeps its emoji (principle 7).
    private func enrich(_ app: GamesLayout.ExternalApp) {
        Task {
            guard let found = await ITunesSearch.lookup(name: app.name),
                  var current = store.externalApp(id: app.id)   // gone if deleted meanwhile
            else { return }
            current.artworkURL = found.artworkUrl512 ?? current.artworkURL
            current.storeURL = found.trackViewUrl ?? current.storeURL
            store.updateExternalApp(current)
            if let artworkURL = found.artworkUrl512 {
                await artwork.fetchArtwork(from: artworkURL, for: app.id)
            }
        }
    }
}

#Preview {
    GamesTabView()
        .environment(GamesLayoutStore(
            modules: [FoodDecisionModule.descriptor],
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("preview-games-tab.json")))
        .environment(ArtworkStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("preview-artwork")))
}

#if DEBUG
#Preview("With a collection") {
    let modules = [FoodDecisionModule.descriptor] + SampleModules.descriptors
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("preview-folder.json")
    let store = GamesLayoutStore(modules: modules, fileURL: url)
    let _ = store.formCollection(target: "sample-stars", dragged: "sample-dice",
                                 named: "Play 🎲")
    GamesTabView()
        .environment(store)
        .environment(ArtworkStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("preview-artwork")))
}
#endif
