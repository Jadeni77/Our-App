import SwiftData
import SwiftUI

/// One album: its photos, and the ways to change what is in it.
///
/// Wears the sub-page chrome contract (`docs/modules/couples-hub.md`) even
/// though it arrives by `NavigationLink` from `AlbumsGridView` rather than
/// straight off `HubRoute`: dreamy background with no moon, hidden toolbar
/// background, dark toolbar items. Every pushed page in this app looks like
/// it belongs to the same place, not just the ones reached directly from Home.
struct AlbumDetailView: View {
    let albumID: UUID

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: Album.visible) private var albums: [Album]
    // Never read directly — same reasoning as `AlbumsGridView`'s `albums`
    // query. `AlbumStore.assets(of:in:)` below is a plain fetch of
    // `AlbumEntry`; without something here observing that model, a photo
    // filed or removed while this exact screen is open — by the other phone,
    // mid-sync — would sit invisible until the view was torn down and rebuilt.
    @Query(filter: AlbumEntry.visible) private var entries: [AlbumEntry]
    @State private var picking = false
    @State private var renaming = false
    @State private var confirmingDelete = false
    @State private var name = ""
    // Same cache the grid reads from (`AlbumsGridView.cover(for:)`,
    // `MemoriesView.cell(_:)`) — a third copy of "read the full 2048px file
    // synchronously on every render" is exactly the mistake Task 5 already
    // caught and fixed once.
    private let thumbnails = MemoryThumbnails.shared

    private var album: Album? { albums.first { $0.id == albumID } }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        ZStack {
            DreamyBackground(showsMoon: false)

            if let album {
                let assets = AlbumStore.assets(of: album, in: context)
                if assets.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(assets, id: \.self) { asset in
                                tile(asset, in: album)
                            }
                        }
                        .padding(.horizontal, 3)
                    }
                }
            }
        }
        .navigationTitle(Text(verbatim: album?.name ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { picking = true } label: { Label("Add photos", systemImage: "plus") }
                    Button { name = album?.name ?? ""; renaming = true } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Label("Delete album", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Rename", isPresented: $renaming) {
            TextField("Name", text: $name)
            Button("Save") {
                guard let album else { return }
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                AlbumStore.rename(album, to: trimmed, in: context)
            }
            Button("Cancel", role: .cancel) {}
        }
        // A tombstone is forever here — there's no trash or restore anywhere
        // in the app — so this is one tap away from "Rename" behind a
        // confirmation, worded around what it does *not* touch: the photos
        // stay exactly where they are, in every other album and in the
        // library, per `AlbumStore.delete`'s own contract.
        .confirmationDialog(Text("Delete this album?"),
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(role: .destructive) { deleteAlbum() } label: { Text("Delete") }
        } message: {
            Text("Its photos aren't deleted — only the album is.")
        }
        .sheet(isPresented: $picking) {
            if let album { PhotoPickerSheet(album: album) }
        }
    }

    /// Dismisses after the tombstone lands — otherwise `album` goes nil the
    /// moment `@Query` excludes it and the screen collapses into a blank
    /// grid under an empty title instead of popping back, the same fix
    /// `MemoryDetailView.delete()` makes for the same reason.
    private func deleteAlbum() {
        guard let album else { return }
        Haptics.tap()
        AlbumStore.delete(album, in: context)
        dismiss()
    }

    @ViewBuilder
    private func tile(_ asset: String, in album: Album) -> some View {
        ZStack {
            if let image = thumbnails.image(for: asset) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                // The record arrived before its picture, which is deliberate:
                // notes and dates are worth having before megabytes land. Also
                // covers a thumbnail that simply hasn't finished loading yet.
                PhotoPlaceholder()
            }
        }
        .frame(height: 116)
        .clipped()
        .task { await thumbnails.loadIfNeeded(asset) }
        .contextMenu {
            Button { AlbumStore.setCover(album, to: asset, in: context) } label: {
                Label("Use as cover", systemImage: "star")
            }
            Button(role: .destructive) {
                AlbumStore.remove(assetID: asset, from: album, in: context)
            } label: {
                Label("Remove from album", systemImage: "minus.circle")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.55))
            Text("No photos in this album yet")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(32)
    }
}

/// The "no picture yet" glyph shared by every grid this file adds — matched to
/// `AlbumsGridView.cover(for:)`'s placeholder rather than each grid quietly
/// inventing its own. Before this fix the feature had four different
/// placeholder styles across four grids for what is exactly the same state.
private struct PhotoPlaceholder: View {
    var body: some View {
        ZStack {
            Color.white.opacity(0.10)
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.55))
        }
    }
}

/// Choosing from the library rather than from the camera roll: everything here
/// is already a picture the two of you have.
///
/// A tap **toggles** membership rather than only ever adding. The original
/// version treated a second tap on an already-filed photo as an add that just
/// happened to do nothing — a silent no-op, which this codebase treats as a
/// bug on sight. Showing which photos are already in via a checkmark, and
/// giving every tap a haptic, means there is no tap here that looks
/// successful and isn't.
private struct PhotoPickerSheet: View {
    let album: Album
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    // Never read directly: without these, neither a photo arriving mid-sync
    // nor this picker's own adds and removes would ever redraw the grid —
    // the same gap `AllPhotosView` had.
    @Query(filter: Photo.visible) private var photos: [Photo]
    @Query(filter: AlbumEntry.visible) private var entries: [AlbumEntry]
    private let thumbnails = MemoryThumbnails.shared

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showsMoon: false)

                let library = PhotoLibrary.all(in: context)
                if library.isEmpty {
                    emptyState
                } else {
                    // One fetch of membership for the whole grid, rather than
                    // asking `AlbumStore.assets(of:in:)` to re-derive it once
                    // per tile per render.
                    let filed = Set(AlbumStore.assets(of: album, in: context))
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(library, id: \.id) { photo in
                                tile(photo, inAlbum: filed.contains(photo.assetID))
                            }
                        }
                        .padding(.horizontal, 3)
                    }
                }
            }
            .navigationTitle(Text("Add photos"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func tile(_ photo: Photo, inAlbum: Bool) -> some View {
        Button {
            Haptics.tap()
            if inAlbum {
                AlbumStore.remove(assetID: photo.assetID, from: album, in: context)
            } else {
                AlbumStore.add(assetID: photo.assetID, to: album,
                               authorID: LocalAuthor.id(), in: context)
            }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                if let image = thumbnails.image(for: photo.assetID) {
                    Image(uiImage: image).resizable().scaledToFill()
                        // Dimmed as well as checked — a colour-blind tap
                        // shouldn't have to tell "in" from "out" by hue alone.
                        .opacity(inAlbum ? 0.55 : 1)
                } else {
                    PhotoPlaceholder()
                }
                if inAlbum {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Theme.indigo)
                        .font(.system(size: 20))
                        .padding(6)
                }
            }
            .frame(height: 116)
            .clipped()
            .task { await thumbnails.loadIfNeeded(photo.assetID) }
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.55))
            Text("No photos yet")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(32)
    }
}

/// Everything, filed or not — so nothing you own is unreachable because
/// neither of you got round to putting it somewhere.
struct AllPhotosView: View {
    @Environment(\.modelContext) private var context
    // Never read directly — the same shape as `AlbumsGridView`'s `albums`
    // query. `PhotoLibrary.all(in:)` below is a plain fetch; without this,
    // nothing would tell the view to redraw when a photo is composed
    // elsewhere in the app or arrives from the other phone's sync while this
    // screen happens to be open.
    @Query(filter: Photo.visible) private var photos: [Photo]
    private let thumbnails = MemoryThumbnails.shared
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        ZStack {
            DreamyBackground(showsMoon: false)

            let library = PhotoLibrary.all(in: context)
            if library.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(library, id: \.id) { photo in
                            ZStack {
                                if let image = thumbnails.image(for: photo.assetID) {
                                    Image(uiImage: image).resizable().scaledToFill()
                                } else {
                                    PhotoPlaceholder()
                                }
                            }
                            .frame(height: 116)
                            .clipped()
                            .task { await thumbnails.loadIfNeeded(photo.assetID) }
                        }
                    }
                    .padding(.horizontal, 3)
                }
            }
        }
        .navigationTitle(Text("All photos"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.55))
            Text("No photos yet")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(32)
    }
}

#Preview {
    NavigationStack {
        AlbumDetailView(albumID: UUID())
    }
    .modelContainer(try! Persistence.makeContainer(inMemory: true))
}
