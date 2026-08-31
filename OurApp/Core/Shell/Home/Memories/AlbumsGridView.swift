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
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                // `MemoryPhotoStore` reads the stored copy straight off disk —
                // the same path `AlbumDetailView` will use, so a cover looks
                // identical wherever it's shown rather than depending on
                // which cache happened to warm first.
                if let asset = AlbumStore.cover(of: album, in: context),
                   let image = MemoryPhotoStore().image(for: asset) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    // An empty album says so rather than showing a broken tile.
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(verbatim: album.name)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
            Text("\(AlbumStore.count(of: album, in: context)) photos")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

#Preview {
    NavigationStack { AlbumsGridView() }
        .modelContainer(try! Persistence.makeContainer(inMemory: true))
}
