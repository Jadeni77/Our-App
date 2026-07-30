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
    @State private var externalSheet: ExternalSheet?
    @State private var deletingExternalApp: GamesLayout.ExternalApp?
    @State private var launchFailedApp: GamesLayout.ExternalApp?
    /// Case-2 convergence (owners' spec, 2026-07-30): a tile that keeps
    /// bouncing to the App Store is either not installed (fine) or missing
    /// its link — after the second bounce, offer the repair once.
    @State private var storeBounces: [UUID: Int] = [:]
    @State private var linkOfferApp: GamesLayout.ExternalApp?

    /// One sheet for both S7 flows — two stacked `.sheet` modifiers on one
    /// view are exactly the presentation race this codebase already ruled on.
    private enum ExternalSheet: Identifiable {
        case add
        case edit(GamesLayout.ExternalApp)

        var id: String {
            switch self {
            case .add: "add"
            case .edit(let app): app.id.uuidString
            }
        }
    }
    @State private var jiggle = JiggleController()
    @State private var tileFrames: [GamesLayout.ItemID: CGRect] = [:]
    @State private var dragLocation: CGPoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var folderNamespace

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 18), count: 4)

    var body: some View {
        ZStack {
            DreamyBackground()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 22) {
                    ForEach(displayedItems) { item in
                        tile(for: item)
                    }
                }
                .animation(Theme.springy, value: displayedItems.map(\.id))
                .padding(.horizontal, 20)
                // Edit mode drops the grid below the + and Done pills so the
                // corner tiles (and the first tile's delete badge) stay tappable.
                .padding(.top, jiggle.isEditing ? 72 : 24)
            }
            // The scroll area owns every touch the tiles don't, so the enter
            // gesture lives here: holding anywhere (a tile or empty space)
            // starts arranging. `simultaneousGesture` matters twice: it fires
            // at the 0.5 s mark while the finger is still down (a plain
            // onLongPressGesture on a ScrollView only recognizes on lift),
            // and it sees touches that begin on tiles, so this is the ONE
            // jiggle entry point for the whole grid. **Done** is the only
            // exit — a background tap competed with tile taps and read as
            // flaky (owners' call, 2026-07-30).
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                    guard !jiggle.isEditing else { return }
                    Haptics.tap()
                    withAnimation(Theme.springy) { jiggle.isEditing = true }
                }
            )

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
                    onLaunchExternal: { external in
                        self.openCollectionID = nil
                        renamingNewCollection = false
                        launchExternal(external)
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
                    externalSheet = .add
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
        .sheet(item: $externalSheet) { sheet in
            switch sheet {
            case .add:
                AddExternalAppSheet(
                    onCommit: commitNewExternalApp,
                    onEditExisting: { app in
                        // Hop past the add sheet's dismissal, then reopen as
                        // that tile's editor — the redo path for dead links.
                        Task { @MainActor in externalSheet = .edit(app) }
                    })
            case .edit(let app):
                AddExternalAppSheet(existing: app, onCommit: commitEditedExternalApp)
            }
        }
        // A centered alert, not a bottom sheet — the badge that summons it
        // sits at the top of the screen (owners' UX call, 2026-07-30).
        .alert(
            Text(verbatim: deletingExternalApp?.name ?? ""),
            isPresented: Binding(
                get: { deletingExternalApp != nil },
                set: { if !$0 { deletingExternalApp = nil } }),
            presenting: deletingExternalApp
        ) { app in
            Button("Remove", role: .destructive) {
                Haptics.tap()
                withAnimation(Theme.springy) { store.deleteExternalApp(id: app.id) }
                artwork.forget(app.id)
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            Text(verbatim: linkOfferApp?.name ?? ""),
            isPresented: Binding(
                get: { linkOfferApp != nil },
                set: { if !$0 { linkOfferApp = nil } }),
            presenting: linkOfferApp
        ) { app in
            Button("Set up link") {
                // Hop past the alert's dismissal before presenting the sheet.
                Task { @MainActor in externalSheet = .edit(app) }
            }
            Button("Open App Store", role: .cancel) {
                // A standing choice, not a dismissal (owners' call,
                // 2026-07-30): future taps skip the guessing entirely.
                if var declined = store.externalApp(id: app.id),
                   !declined.prefersStore {
                    declined.prefersStore = true
                    store.updateExternalApp(declined)
                }
                openStore(app)
            }
        } message: { _ in
            Text("Opens the App Store every time — link it to launch directly?")
        }
        .alert(
            Text(verbatim: launchFailedApp?.name ?? ""),
            isPresented: Binding(
                get: { launchFailedApp != nil },
                set: { if !$0 { launchFailedApp = nil } }),
            presenting: launchFailedApp
        ) { app in
            Button("Edit") {
                // Hop past the alert's dismissal transaction before
                // presenting the sheet, so the two presentations can't race.
                Task { @MainActor in externalSheet = .edit(app) }
            }
            Button("OK", role: .cancel) {}
        } message: { _ in
            Text("Couldn't open")
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
                    // Badge inside the wobble so it jiggles with its tile.
                    .overlay(alignment: .topLeading) {
                        // The one deletion the springboard allows (S7):
                        // externals are user-added, modules never delete.
                        if jiggle.isEditing { deleteBadge(external) }
                    }
                    .modifier(Wobble(active: jiggle.isEditing, reduceMotion: reduceMotion))
                    .onTapGesture {
                        if jiggle.isEditing {
                            // Editing is how a wrong scheme gets fixed after a
                            // soft fallback (store page opened, no alert) —
                            // jiggle-tap is the way in (owners' find, 2026-07-30).
                            Haptics.tap()
                            externalSheet = .edit(external)
                        } else {
                            launchExternal(external)
                        }
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
        // The sheet pre-dressed the tile when it could — only chase
        // enrichment for the fail-soft path (offline add, lookup miss).
        if app.artworkURL == nil {
            enrich(app)
        }
    }

    private func commitEditedExternalApp(_ edited: GamesLayout.ExternalApp) {
        // Merge only the sheet's fields onto the live entry — enrichment may
        // have written artwork/store links after the sheet snapshotted it.
        guard var live = store.externalApp(id: edited.id) else { return }
        live.name = edited.name
        live.launchURL = edited.launchURL
        live.prefersStore = edited.prefersStore   // cleared by a verified link
        store.updateExternalApp(live)
        enrich(live)   // refresh the store link/artwork if the name changed
    }

    /// S7 launch path (principle 7 — never a dead end): the saved link,
    /// else a self-healing walk of the verified catalog and the likely
    /// candidates (a success opens the game AND repairs the tile), else the
    /// App Store page, else a friendly message with an Edit way out.
    private func launchExternal(_ app: GamesLayout.ExternalApp) {
        Haptics.tap()
        // "Open App Store" at the offer is a standing choice: no guessing,
        // no prompts — straight to the store, with a gentle re-offer every
        // third open in case they've changed their mind.
        if app.prefersStore {
            let bounces = (storeBounces[app.id] ?? 0) + 1
            storeBounces[app.id] = bounces
            if bounces % 3 == 0 {
                linkOfferApp = app
            } else {
                openStore(app)
            }
            return
        }
        Task {
            // Ordered attempts: the saved link, then what we know, then the
            // likely guesses — filtered so iOS is only asked to open apps it
            // has confirmed exist (or ones it can't answer for).
            let ordered = ([app.launchURL?.absoluteString,
                            store.verifiedScheme(for: app.name)].compactMap { $0 }
                + SchemeCatalog.candidates(from: app.name))
            let attempts = SchemeCatalog.plan(
                candidates: ordered,
                declared: SchemeCatalog.declaredSchemes,
                canOpen: { candidate in
                    URL(string: candidate).map {
                        UIApplication.shared.canOpenURL($0)
                    } ?? false
                })

            for candidate in attempts {
                guard let url = URL(string: candidate) else { continue }
                let started = Date()
                if await UIApplication.shared.open(url) {
                    // A working launch is proof: keep the tile and the
                    // catalog learning from it.
                    if var healed = store.externalApp(id: app.id),
                       healed.launchURL != url {
                        healed.launchURL = url
                        store.updateExternalApp(healed)
                    }
                    store.learnScheme(name: app.name, scheme: candidate)
                    return
                }
                // A missing scheme fails in milliseconds; a human dismissing
                // iOS's "wants to open" prompt takes seconds. A slow "no" is
                // the owner declining — stop everything, including the store.
                if Date().timeIntervalSince(started) > 1.5 { return }
            }
            openStoreOrFail(app)
        }
    }

    private func openStoreOrFail(_ app: GamesLayout.ExternalApp) {
        let bounces = (storeBounces[app.id] ?? 0) + 1
        storeBounces[app.id] = bounces
        // The second bounce in a session is the signal: if the app were
        // simply not installed, the store's Get button would have ended the
        // story. Offer the direct-link repair once, then stay quiet.
        if bounces == 2 {
            linkOfferApp = app
            return
        }
        openStore(app)
    }

    private func openStore(_ app: GamesLayout.ExternalApp) {
        guard let storeURL = app.storeURL else { launchFailedApp = app; return }
        UIApplication.shared.open(storeURL, options: [:]) { opened in
            if !opened { launchFailedApp = app }
        }
    }

    private func deleteBadge(_ app: GamesLayout.ExternalApp) -> some View {
        Button {
            Haptics.tap()
            deletingExternalApp = app
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 22))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.4))
                // 44pt hit target (HIG minimum — established review ruling).
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .offset(x: -14, y: -14)
        .accessibilityLabel(Text("Remove"))
    }

    /// Fire-and-forget iTunes enrichment: official artwork + App Store page
    /// by name. Every step fails soft — the tile keeps its emoji (principle 7).
    private func enrich(_ app: GamesLayout.ExternalApp) {
        Task {
            guard let found = await ITunesSearch.lookup(name: app.name),
                  // Fuzzy search must never dress a tile with a stranger's
                  // artwork — only plausible title matches count.
                  ITunesSearch.plausibleMatch(typed: app.name,
                                              trackName: found.trackName),
                  var current = store.externalApp(id: app.id)   // gone if deleted meanwhile
            else { return }
            let previousArtworkURL = current.artworkURL
            current.artworkURL = found.artworkUrl512 ?? current.artworkURL
            current.storeURL = found.trackViewUrl ?? current.storeURL
            store.updateExternalApp(current)
            if let artworkURL = found.artworkUrl512, artworkURL != previousArtworkURL {
                // New art — first fetch, or a rename resolved to a different
                // app — so replace whatever icon is cached.
                await artwork.refreshArtwork(from: artworkURL, for: app.id)
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
