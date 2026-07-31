// OurApp/Core/Shell/GamesTab/FolderOverlayView.swift
import SwiftUI

/// A collection zoomed open (games-springboard.md): the name above a glass
/// panel of members, 3 columns — name editable while arranging, and a
/// long-press on any member starts arranging right from in here.
struct FolderOverlayView: View {
    let collection: GamesLayout.Collection
    let store: GamesLayoutStore
    let isEditing: Bool
    var startsRenaming = false
    /// Long-press on a member wants edit mode; the root grid owns that state,
    /// so the overlay asks rather than flips it locally.
    let onBeginEditing: () -> Void
    let onLaunch: (ModuleDescriptor) -> Void
    /// External members launch through the root's S7 fallback chain.
    let onLaunchExternal: (GamesLayout.ExternalApp) -> Void
    let onClose: () -> Void

    @State private var draftName = ""
    @FocusState private var nameFocused: Bool
    @State private var jiggle = JiggleController()   // folder-local drags
    @State private var memberFrames: [GamesLayout.ItemID: CGRect] = [:]
    @State private var panelFrame: CGRect = .zero
    @State private var dragLocation: CGPoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    var body: some View {
        ZStack {
            Theme.scrim
                .ignoresSafeArea()
                .onTapGesture { commitNameAndClose() }

            VStack(spacing: 16) {
                // Name sits above the grid, like an open iOS folder's title.
                if isEditing {
                    TextField("Collection name", text: $draftName)
                        .focused($nameFocused)
                        .multilineTextAlignment(.center)
                        .font(Theme.display(20))
                        .foregroundStyle(.white)
                        .submitLabel(.done)
                        .onSubmit { commitName() }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .glassCard(cornerRadius: 18)
                } else {
                    Text(verbatim: collection.name)      // user data (S6)
                        .font(Theme.display(20))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        // Match the rename pill's height so the grid doesn't
                        // shift under a finger mid-long-press when edit begins.
                        .padding(.vertical, 10)
                }

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(collection.members, id: \.self) { memberID in
                        // Gate on resolvability so an unresolvable key can't
                        // produce a phantom cell wearing live gestures.
                        if store.module(for: memberID) != nil
                            || store.externalApp(forKey: memberID) != nil {
                            memberTile(memberID)
                        }
                    }
                }
                .padding(20)
                .glassCard(cornerRadius: 28)
            }
            // "Inside the folder" means the whole folder — name row included:
            // measured on the VStack (pre-padding), so dropping a member on
            // the title doesn't read as "drag it out" (post-#14 follow-up).
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("folder")) }
                action: { panelFrame = $0 }
            .padding(.horizontal, 36)

            if let draggedID = jiggle.draggedItem, let location = dragLocation {
                ghost(for: draggedID)
                    .frame(width: 80)
                    .scaleEffect(1.08)
                    .position(location)
                    .allowsHitTesting(false)
                    .zIndex(3)
            }
        }
        .coordinateSpace(name: "folder")
        .onAppear {
            draftName = collection.name
            if startsRenaming { nameFocused = true }
            jiggle.isEditing = isEditing
        }
        .onChange(of: isEditing) { _, newValue in
            jiggle.isEditing = newValue
            if !newValue {
                // Root exited edit mode (Done / background tap) while this
                // folder was open — Done must not silently drop an in-flight
                // rename, so commit it; then drop any in-flight member drag
                // so a cancelled gesture can't strand a ghost in here either.
                commitName()
                dragLocation = nil
                _ = jiggle.endDrag()
            }
        }
    }

    /// One member tile — module or external. The folder-local drag machinery
    /// keys everything as `.app(memberKey)`: identities never leave this view,
    /// so the uniform keying keeps frames, order, and intents aligned without
    /// caring which kind a member is.
    @ViewBuilder
    private func memberTile(_ memberID: String) -> some View {
        Group {
            if let module = store.module(for: memberID) {
                AppTileView(module: module)
                    // Guards read live state through the observable controller
                    // (not the captured `isEditing` prop): the long-press below
                    // flips edit mode mid-touch, and a stale snapshot could let
                    // the lift still launch the module.
                    .onTapGesture {
                        guard !jiggle.isEditing else { return }
                        Haptics.tap()
                        onLaunch(module)
                    }
                    .accessibilityLabel(Text(module.name))
            } else if let external = store.externalApp(forKey: memberID) {
                ExternalTileView(app: external)
                    .onTapGesture {
                        guard !jiggle.isEditing else { return }
                        Haptics.tap()
                        onLaunchExternal(external)
                    }
                    .accessibilityLabel(Text(verbatim: external.name))
            }
        }
        .modifier(Wobble(active: jiggle.isEditing, reduceMotion: reduceMotion))
        .onLongPressGesture(minimumDuration: 0.5) {
            guard !jiggle.isEditing else { return }
            Haptics.tap()
            onBeginEditing()
        }
        .gesture(jiggle.isEditing ? memberDrag(memberID) : nil)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named("folder"))
        } action: { memberFrames[.app(memberID)] = $0 }
        .opacity(jiggle.draggedItem == .app(memberID) ? 0.001 : 1)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func ghost(for id: GamesLayout.ItemID) -> some View {
        if case .app(let memberID) = id {
            if let module = store.module(for: memberID) {
                AppTileView(module: module)
            } else if let external = store.externalApp(forKey: memberID) {
                ExternalTileView(app: external)
            }
        }
    }

    private func memberDrag(_ memberID: String) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("folder"))
            .onChanged { value in
                // Keyed on identity, not nil — see the matching comment in
                // GamesTabView.dragGesture(for:): a cancelled drag never
                // fires `onEnded`, so this must still recognize a genuinely
                // new drag rather than inherit a stale dragged member.
                if jiggle.draggedItem != .app(memberID) {
                    Haptics.tap()
                    jiggle.beginDrag(.app(memberID))
                }
                dragLocation = value.location
                jiggle.updateDrag(location: value.location, frames: memberFrames,
                                  order: collection.members.map { .app($0) }, now: Date())
            }
            .onEnded { value in
                let intent = jiggle.endDrag()
                dragLocation = nil
                if !panelFrame.contains(value.location) {
                    // Out of the panel → back to the root grid (S5 dissolves if last).
                    withAnimation(Theme.springy) {
                        store.moveMemberToRoot(memberID, from: collection.id)
                    }
                    Haptics.tap()
                    if !store.layout.items.contains(where: { $0.id == .collection(collection.id) }) {
                        onClose()                    // collection dissolved under us
                    }
                } else {
                    // Members can hover each other, but folders never nest —
                    // map target intents to "land at the hovered member's slot".
                    let insertAt: Int? = switch intent {
                    case .reorder(let index): index
                    case .target(.app(let other)), .armedTarget(.app(let other)):
                        collection.members.filter { $0 != memberID }.firstIndex(of: other)
                    default: nil
                    }
                    if let insertAt {
                        withAnimation(Theme.springy) {
                            store.moveMember(in: collection.id, member: memberID,
                                             toIndex: insertAt)
                        }
                        Haptics.tap()
                    }
                }
            }
    }

    private func commitName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != collection.name {
            store.renameCollection(collection.id, to: trimmed)
        }
        // Realign the draft with what's actually stored: the view keeps its
        // identity across the rename (onAppear won't re-seed), so an
        // abandoned draft would otherwise resurface on the next edit.
        draftName = trimmed.isEmpty ? collection.name : trimmed
    }

    private func commitNameAndClose() {
        commitName()
        onClose()
    }
}
