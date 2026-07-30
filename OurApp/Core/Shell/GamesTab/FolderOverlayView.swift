// OurApp/Core/Shell/GamesTab/FolderOverlayView.swift
import SwiftUI

/// A collection zoomed open (games-springboard.md): glass panel, 3-column
/// grid of members, the name shown beneath — editable while arranging.
struct FolderOverlayView: View {
    let collection: GamesLayout.Collection
    let store: GamesLayoutStore
    let isEditing: Bool
    var startsRenaming = false
    let onLaunch: (ModuleDescriptor) -> Void
    let onClose: () -> Void

    @State private var draftName = ""
    @FocusState private var nameFocused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { commitNameAndClose() }

            VStack(spacing: 16) {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(collection.members, id: \.self) { memberID in
                        if let module = store.module(for: memberID) {
                            AppTileView(module: module)
                                .onTapGesture {
                                    guard !isEditing else { return }
                                    Haptics.tap()
                                    onLaunch(module)
                                }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityLabel(Text(module.name))
                        }
                    }
                }
                .padding(20)
                .glassCard(cornerRadius: 28)

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
                    Text(collection.name)      // verbatim — user data (S6)
                        .font(Theme.display(20))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 36)
        }
        .onAppear {
            draftName = collection.name
            if startsRenaming { nameFocused = true }
        }
    }

    private func commitName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != collection.name {
            store.renameCollection(collection.id, to: trimmed)
        }
    }

    private func commitNameAndClose() {
        commitName()
        onClose()
    }
}
