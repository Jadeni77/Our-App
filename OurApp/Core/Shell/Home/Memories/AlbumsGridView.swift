import SwiftData
import SwiftUI

/// Every album, as covers.
///
/// Two columns with a name and a count under each — the layout cue taken from
/// 微爱's 相册 tab. The art, type and colour are this app's own.
///
/// A tile opens `AlbumDetailView`; the row above the grid opens `AllPhotosView`
/// — the library itself, not just what's been filed, so nothing either of you
/// owns is unreachable for want of an album.
struct AlbumsGridView: View {
    @Environment(\.modelContext) private var context
    // Never read directly — `AlbumStore.albums(in:)` below is the one true
    // ordering. This exists purely so SwiftData tells the view to redraw
    // when an album is created, renamed or tombstoned; a plain function call
    // to the store wouldn't be observed on its own.
    @Query(filter: Album.visible) private var albums: [Album]
    // Never read directly either, and here for the same reason — but for the
    // two models this view *renders* rather than the one it lists. The body
    // below reads `AlbumEntry` through `AlbumStore.summary(of:)`, once per tile,
    // for every cover and count; and `Photo` through `PhotoLibrary.all(in:)`,
    // for the All photos total. Both are plain fetches, and a plain fetch of a
    // model nothing here observes is a number that stops changing: she files
    // four photos into an album while I'm sitting on this grid, her tiles
    // update, and mine keep the old count and the old cover indefinitely.
    // `AlbumDetailView` states this rule and names this file; it was true of
    // that screen and not of this one.
    @Query(filter: AlbumEntry.visible) private var entries: [AlbumEntry]
    @Query(filter: Photo.visible) private var photos: [Photo]
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
            NavigationLink { AllPhotosView() } label: {
                HStack {
                    Image(systemName: "photo.stack")
                    Text("All photos")
                    Spacer()
                    Text("\(PhotoLibrary.all(in: context).count)")
                }
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .glassCard(cornerRadius: 18)
            .padding(.horizontal, 14)
            .padding(.top, 8)

            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(AlbumStore.albums(in: context)) { album in
                    NavigationLink { AlbumDetailView(albumID: album.id) } label: {
                        cover(for: album)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
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
            // Not the shared `Name` key: its Chinese is 名字, a *person's* given
            // name, which is what it means everywhere else it is used. An album
            // is 名称.
            TextField("Album name", text: $newName)
            Button("Create") {
                guard !trimmedNewName.isEmpty else { return }
                AlbumStore.create(name: trimmedNewName, authorID: LocalAuthor.id(),
                                  in: context)
            }
            // No `.disabled` here on purpose, even though the house pattern
            // elsewhere (`SpecialDateEditorSheet`) is to disable a confirm
            // button that can't do anything yet. `newName` starts empty every
            // time this alert opens, so a `.disabled(trimmedNewName.isEmpty)`
            // button would start disabled on first presentation — and on
            // iOS 17 (this project's deployment target) a `Button` inside an
            // `.alert` that starts disabled never fires its action at all,
            // even after the field is filled in and the button re-enables.
            // The guard above is the only validation this needs; a button
            // that can't do anything already says so by doing nothing.
            Button("Cancel", role: .cancel) {}
        }
    }

    private var trimmedNewName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
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
            // **Keyed on the cover, not bare.** A tile's identity is its album,
            // so a plain `.task` fires once and never again — set the cover to
            // a photo nothing had thumbnailed yet and the tile sat on the
            // "empty album" glyph, because the one load that would have fixed
            // it had already run against the previous cover.
            .task(id: summary.cover) {
                if let asset = summary.cover { await thumbnails.loadIfNeeded(asset) }
            }

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
