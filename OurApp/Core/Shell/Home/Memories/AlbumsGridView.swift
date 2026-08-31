import SwiftData
import SwiftUI

/// Every album, as covers.
///
/// Two columns with a name and a count under each — the layout cue taken from
/// 微爱's 相册 tab. The art, type and colour are this app's own.
///
/// Tiles don't navigate yet — that lands with `AlbumDetailView` in the next
/// task. Until then this is a read-only grid plus the one write the feature
/// already needs: naming a new album.
struct AlbumsGridView: View {
    @Environment(\.modelContext) private var context
    // Never read directly — `AlbumStore.albums(in:)` below is the one true
    // ordering. This exists purely so SwiftData tells the view to redraw
    // when an album is created, renamed or tombstoned; a plain function call
    // to the store wouldn't be observed on its own.
    @Query(filter: Album.visible) private var albums: [Album]
    @State private var naming = false
    @State private var newName = ""
    // Same cache `MemoriesView.cell(_:)` reads its grid thumbnails from —
    // one place that has already learned to load off-main-thread and to
    // remember a miss, rather than a second copy of that lesson here.
    private let thumbnails = MemoryThumbnails.shared

    private let columns = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(AlbumStore.albums(in: context)) { album in
                    cover(for: album)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { newName = ""; naming = true } label: {
                    Label("New album", systemImage: "plus")
                        .foregroundStyle(.white)
                }
            }
        }
        .alert("New album", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Create") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                AlbumStore.create(name: name, authorID: LocalAuthor.id(), in: context)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func cover(for album: Album) -> some View {
        // One fetch of the album's memberships for both the cover and the
        // count, rather than the two `AlbumStore.cover(of:)` and
        // `AlbumStore.count(of:)` would each run alone, once per tile per
        // render.
        let summary = AlbumStore.summary(of: album, in: context)
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                // Cache-first, same as `MemoriesView.cell(_:)`: a hit here is
                // a thumbnail already decoded off-main-thread by an earlier
                // `loadIfNeeded`, not a fresh disk read on every render.
                if let asset = summary.cover, let image = thumbnails.image(for: asset) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    // Covers a genuinely empty album and a cover still
                    // loading alike — the load, once it lands, redraws this
                    // in place because `MemoryThumbnails` is `@Observable`.
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .task { if let asset = summary.cover { await thumbnails.loadIfNeeded(asset) } }

            Text(verbatim: album.name)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
            Text("\(summary.count) photos")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

#Preview {
    NavigationStack { AlbumsGridView() }
        .modelContainer(try! Persistence.makeContainer(inMemory: true))
}
