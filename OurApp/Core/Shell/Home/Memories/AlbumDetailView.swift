import SwiftData
import SwiftUI

/// One album: its photos, and the ways to change what is in it.
struct AlbumDetailView: View {
    let albumID: UUID

    @Environment(\.modelContext) private var context
    @Query(filter: Album.visible) private var albums: [Album]
    @State private var picking = false
    @State private var renaming = false
    @State private var name = ""
    // Same cache the grid reads from (`AlbumsGridView.cover(for:)`,
    // `MemoriesView.cell(_:)`) — a third copy of "read the full 2048px file
    // synchronously on every render" is exactly the mistake Task 5 already
    // caught and fixed once.
    private let thumbnails = MemoryThumbnails.shared

    private var album: Album? { albums.first { $0.id == albumID } }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        ScrollView {
            if let album {
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(AlbumStore.assets(of: album, in: context), id: \.self) { asset in
                        tile(asset, in: album)
                    }
                }
                .padding(.horizontal, 3)
            }
        }
        .navigationTitle(Text(verbatim: album?.name ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { picking = true } label: { Label("Add photos", systemImage: "plus") }
                    Button { name = album?.name ?? ""; renaming = true } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    if let album {
                        Button(role: .destructive) {
                            AlbumStore.delete(album, in: context)
                        } label: {
                            Label("Delete album", systemImage: "trash")
                        }
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
        .sheet(isPresented: $picking) {
            if let album { PhotoPickerSheet(album: album) }
        }
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
                Color.white.opacity(0.08)
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
}

/// Choosing from the library rather than from the camera roll: everything here
/// is already a picture the two of you have.
private struct PhotoPickerSheet: View {
    let album: Album
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    private let thumbnails = MemoryThumbnails.shared

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(PhotoLibrary.all(in: context), id: \.id) { photo in
                        Button {
                            AlbumStore.add(assetID: photo.assetID, to: album,
                                           authorID: LocalAuthor.id(), in: context)
                        } label: {
                            ZStack {
                                if let image = thumbnails.image(for: photo.assetID) {
                                    Image(uiImage: image).resizable().scaledToFill()
                                } else {
                                    Color.secondary.opacity(0.2)
                                }
                            }
                            .frame(height: 116)
                            .clipped()
                            .task { await thumbnails.loadIfNeeded(photo.assetID) }
                        }
                    }
                }
                .padding(.horizontal, 3)
            }
            .navigationTitle(Text("Add photos"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Everything, filed or not — so nothing you own is unreachable because
/// neither of you got round to putting it somewhere.
struct AllPhotosView: View {
    @Environment(\.modelContext) private var context
    private let thumbnails = MemoryThumbnails.shared
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(PhotoLibrary.all(in: context), id: \.id) { photo in
                    ZStack {
                        if let image = thumbnails.image(for: photo.assetID) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Color.white.opacity(0.08)
                        }
                    }
                    .frame(height: 116)
                    .clipped()
                    .task { await thumbnails.loadIfNeeded(photo.assetID) }
                }
            }
            .padding(.horizontal, 3)
        }
        .navigationTitle(Text("All photos"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AlbumDetailView(albumID: UUID())
    }
    .modelContainer(try! Persistence.makeContainer(inMemory: true))
}
