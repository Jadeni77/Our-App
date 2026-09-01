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
    // Same reasoning again, one model further down: `AlbumSections` groups by
    // `Photo.takenAt`, and a photo dated — or simply filed — by the other
    // phone mid-sync has to regroup and redraw here without leaving the
    // screen, the same way a membership change already does.
    @Query(filter: Photo.visible) private var photos: [Photo]
    @State private var picking = false
    @State private var renaming = false
    @State private var confirmingDelete = false
    @State private var name = ""
    @State private var editingCaption = false
    @State private var captionText = ""
    /// What "Set date" changes — one photo from its own context menu, or
    /// every photo in a section from the section heading's own action. Both
    /// funnel into the same sheet, so there is one date-setting UI, not two.
    @State private var settingDate: DateTarget?
    // Same cache the grid reads from (`AlbumsGridView.cover(for:)`,
    // `MemoriesView.cell(_:)`) — a third copy of "read a file synchronously
    // on every render" is exactly the mistake Task 5 already caught and
    // fixed once. The hero below reads this object's *full-size* tier
    // (`MemoryThumbnails.fullImage`), not the 400px one the grid tiles use.
    private let thumbnails = MemoryThumbnails.shared

    private var album: Album? { albums.first { $0.id == albumID } }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        ZStack {
            DreamyBackground(showsMoon: false)

            if let album {
                // The album's own members, then the `Photo` rows behind them —
                // `AlbumSections` groups by day, and the day lives on `Photo`,
                // not on the bare asset id the old flat grid was content with.
                //
                // One fetch of the live memberships serves the cover, the
                // count and the member list together (`AlbumStore.summary(of:)`'s
                // own reasoning) — asking `cover(of:)` and `assets(of:)`
                // separately paid for the same fetch twice on every render.
                let summary = AlbumStore.summary(of: album, in: context)
                let memberSet = Set(summary.assetIDs)
                let albumPhotos = photos.filter { memberSet.contains($0.assetID) }
                // A membership can arrive before its `Photo` row does
                // (`AlbumStore.entries(of:)`'s own doc comment). Grouping by
                // day needs a `Photo` to know which heading a photo belongs
                // under, so one of these can't go through `AlbumSections` —
                // but dropping it from the screen entirely would make it
                // invisible *and* unremovable: no tile to long-press, and
                // `PhotoPickerSheet` only ever lists `Photo` rows.
                let orphanAssetIDs = AlbumStore.orphanedAssets(in: summary.assetIDs,
                                                               notMatching: albumPhotos)
                let sections = AlbumSections.sections(for: albumPhotos)

                ScrollView {
                    // The generous gap the reference has between sections —
                    // applies equally above the first one, so the hero reads
                    // as its own block rather than crowding the first date.
                    LazyVStack(alignment: .leading, spacing: 28) {
                        hero(for: album, cover: summary.cover, count: summary.count)

                        if sections.isEmpty && orphanAssetIDs.isEmpty {
                            // Centered rather than left-hugging the leading
                            // edge the section headings use — this is a
                            // message about the whole page, not a heading of
                            // its own.
                            emptyState.frame(maxWidth: .infinity)
                        } else {
                            ForEach(sections) { section in
                                sectionView(section, in: album)
                            }
                            if !orphanAssetIDs.isEmpty {
                                orphanGrid(orphanAssetIDs, in: album)
                            }
                        }
                    }
                    .padding(.bottom, 24)
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
                    Button { captionText = album?.caption ?? ""; editingCaption = true } label: {
                        Label("Edit caption", systemImage: "text.quote")
                    }
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Label("Delete album", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        // **Leave when the album does, however it went.**
        //
        // `deleteAlbum()` already dismisses after my own tap, but that covers
        // exactly one of the two ways an album disappears. The other is hers:
        // I'm in 🎀 picking a cover, she deletes it, `album` goes nil, and this
        // screen used to sit there rendering nothing but the background under
        // an empty title — with a menu still offering three actions that
        // silently did nothing ("Add photos" opened an empty sheet, "Rename"
        // and "Delete album" hit `guard let album else { return }`).
        //
        // Dismissing rather than showing "This album was deleted": there is
        // nothing left on this screen to look at, every action it offers is
        // gone with the record, and popping back to the grid is where the album
        // no longer being there is legible. A dedicated dead-end state would be
        // a page whose only content is an apology.
        .onChange(of: album == nil) { _, gone in
            if gone { dismiss() }
        }
        .alert("Rename", isPresented: $renaming) {
            // `Album name`, not the shared `Name` key — that one's Chinese is
            // 名字, a person's given name. Same reasoning as the New album
            // alert in `AlbumsGridView`.
            TextField("Album name", text: $name)
            Button("Save") {
                guard let album, !trimmedName.isEmpty else { return }
                AlbumStore.rename(album, to: trimmedName, in: context)
            }
            // Blank or all-spaces used to dismiss as though it had saved. The
            // house pattern is `SpecialDateEditorSheet`'s: disable the confirm.
            .disabled(trimmedName.isEmpty)
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
        .sheet(isPresented: $editingCaption) {
            NavigationStack {
                Form {
                    // Free text, and no guard on Save below — a blank caption
                    // is `Album.caption`'s own default state, not an invalid
                    // one, unlike the name the `Rename` alert above refuses
                    // to leave empty.
                    TextField("Caption", text: $captionText, axis: .vertical)
                }
                .navigationTitle(Text("Edit caption"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { editingCaption = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { saveCaption() }
                    }
                }
            }
        }
        .sheet(item: $settingDate) { target in
            SetDateSheet(photos: target.photos)
        }
    }

    /// Dismisses after the tombstone lands — otherwise `album` goes nil the
    /// moment `@Query` excludes it and the screen collapses into a blank
    /// grid under an empty title instead of popping back, the same fix
    /// `MemoryDetailView.delete()` makes for the same reason.
    ///
    /// The `onChange(of: album == nil)` above would catch this too, and does
    /// catch the case this cannot — her delete. Kept anyway: dismissing on the
    /// tap that caused it is immediate and doesn't wait on a query update, and
    /// dismissing twice costs nothing.
    private func deleteAlbum() {
        guard let album else { return }
        Haptics.tap()
        AlbumStore.delete(album, in: context)
        dismiss()
    }

    /// The couple's own line about the album — allowed to land blank, unlike
    /// a name. Trimmed the same way `rename` trims one, so a stray leading or
    /// trailing return from the keyboard doesn't linger forever.
    private func saveCaption() {
        guard let album else { return }
        Haptics.tap()
        album.caption = captionText.trimmingCharacters(in: .whitespacesAndNewlines)
        album.updatedAt = .now
        try? context.save()
        editingCaption = false
    }

    /// The album's cover, full-bleed, with its name, count and caption
    /// legible over it — the "this is a place, not a pile of squares" cue
    /// 微爱's album screen has and the old flat grid never did. Art, colour
    /// and type are this app's own; only the layout idea is borrowed.
    @ViewBuilder
    private func hero(for album: Album, cover: String?, count: Int) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                // `.fullImage`, not `.image` — the grid's 400px tier, which is
                // what this used to read, upscales about 3x onto a surface
                // this much wider than a grid tile. `MemoryPhotoStore`'s own
                // 2048px copy exists precisely so a full-width, non-grid image
                // like this one doesn't have to.
                if let cover, let image = thumbnails.fullImage(for: cover) {
                    // `scaledToFill` reports the *scaled-up* image size, not
                    // the frame it was asked to fill — for a square photo in
                    // a wide hero that's taller than 220pt, which would push
                    // the whole `ZStack` (and the bottom-aligned text below)
                    // that much taller too, clipping the text mostly off the
                    // bottom rather than sizing it correctly. Pinning the
                    // image to the geometry reader's own resolved size, and
                    // clipping right here, keeps that overflow from ever
                    // reaching the `ZStack`'s layout at all.
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    // No cover — because the album is genuinely empty, or
                    // because the chosen one's full-size copy just hasn't
                    // finished loading — `Color.clear` rather than a second
                    // `DreamyBackground`: the page behind this whole screen
                    // already draws one (a 30fps `TimelineView` with 26
                    // particles and two animated gradients), and stacking a
                    // second copy here showed for the first few frames of
                    // *every* album while its cover loaded, not only a
                    // genuinely empty one. Pinned to the same resolved size
                    // as the image branch above, so which branch is showing
                    // never changes this `ZStack`'s own layout.
                    Color.clear
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }

                LinearGradient(colors: [.clear, .black.opacity(0.7)],
                               startPoint: .top, endPoint: .bottom)

                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: album.name)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                    Text("\(count) photos")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                    // The line the couple writes about the album itself, not
                    // about any one photo in it (`Album.caption`'s own doc).
                    // Nothing shown at all until they write one — a blank
                    // line under the count would read as a mistake, not an
                    // invitation.
                    if !album.caption.isEmpty {
                        Text(verbatim: album.caption)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(2)
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipped()
        // Keyed on the cover, not bare — `AlbumsGridView.cover(for:)`'s own
        // reasoning: a plain `.task` fires once per tile identity, so a cover
        // changed to a photo nothing had loaded yet would never trigger the
        // one load that fixes it. Loads the **full** copy, not the grid's
        // 400px thumbnail — see `MemoryThumbnails.fullImage`.
        .task(id: cover) {
            if let cover { await thumbnails.loadFullIfNeeded(cover) }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: AlbumSections.Section, in album: Album) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading(section)
                .padding(.horizontal, 12)
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(section.photos, id: \.id) { photo in
                    tile(photo, in: album)
                }
            }
            .padding(.horizontal, 3)
        }
    }

    /// Members with no `Photo` row to key a day-section on
    /// (`AlbumStore.orphanedAssets`'s own reasoning) — trailing, past every
    /// dated section and "Sometime", because there's nothing here to sort by
    /// day at all. Always the placeholder glyph, never an attempted image
    /// load: without a `Photo` row there's no confirmed picture behind the id
    /// yet, only a membership. Removable, the one thing that still makes
    /// sense with no `Photo` row present — there's no cover or date to set on
    /// a picture that hasn't arrived.
    @ViewBuilder
    private func orphanGrid(_ assetIDs: [String], in album: Album) -> some View {
        LazyVGrid(columns: columns, spacing: 3) {
            ForEach(assetIDs, id: \.self) { assetID in
                PhotoPlaceholder()
                    .frame(height: 116)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contextMenu {
                        Button(role: .destructive) {
                            AlbumStore.remove(assetID: assetID, from: album, in: context)
                        } label: {
                            Label("Remove from album", systemImage: "minus.circle")
                        }
                    }
            }
        }
        .padding(.horizontal, 3)
    }

    /// "6.11" large next to a smaller "/2024" — the reference's cue, in this
    /// app's own type (`.rounded`, white at two opacities) rather than a copy
    /// of theirs. The calendar button sets one date for every photo the
    /// heading covers at once; the reference shows five photos under one
    /// day, and dating them one at a time would be tedious.
    @ViewBuilder
    private func sectionHeading(_ section: AlbumSections.Section) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let day = section.day {
                // `day` already came out of `SpecialDateSchedule.localDay` in
                // this same (`.current`) calendar, so re-reading its
                // components back through `.current` can't disagree with the
                // grouping that produced it.
                let parts = Calendar.current.dateComponents([.month, .day, .year], from: day)
                Text(verbatim: "\(parts.month ?? 0).\(parts.day ?? 0)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Text(verbatim: "/\(parts.year ?? 0)")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                // The couple sets dates by hand, so this is the trailing
                // section for whichever photos nobody has gotten to yet — the
                // same word `MemoriesView` already uses for undated memories.
                Text("Sometime")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
            }

            Spacer()

            // A bare SF glyph with only an accessibility label read, to
            // anyone sighted, as decoration — nothing on screen said this
            // button sets one date for *every* photo under this heading at
            // once, which is exactly how one tap here could collapse a whole
            // "Sometime" section into a single day with no warning that it
            // was about to touch more than one photo. Visible text now says
            // the scope out loud instead of leaving it to VoiceOver alone.
            Button {
                Haptics.tap()
                settingDate = DateTarget(photos: section.photos)
            } label: {
                Label {
                    Text("Set date for all")
                        .font(.system(.caption, design: .rounded))
                } icon: {
                    Image(systemName: "calendar")
                }
                .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    @ViewBuilder
    private func tile(_ photo: Photo, in album: Album) -> some View {
        ZStack {
            if let image = thumbnails.image(for: photo.assetID) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                // The record arrived before its picture, which is deliberate:
                // notes and dates are worth having before megabytes land. Also
                // covers a thumbnail that simply hasn't finished loading yet.
                PhotoPlaceholder()
            }
        }
        .frame(height: 116)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task { await thumbnails.loadIfNeeded(photo.assetID) }
        .contextMenu {
            Button { AlbumStore.setCover(album, to: photo.assetID, in: context) } label: {
                Label("Use as cover", systemImage: "star")
            }
            Button { settingDate = DateTarget(photos: [photo]) } label: {
                Label("Set date", systemImage: "calendar")
            }
            Button(role: .destructive) {
                AlbumStore.remove(assetID: photo.assetID, from: album, in: context)
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

/// What "Set date" changes, whether it came from one photo's own context menu
/// or a whole section's heading action — one sheet, one Save, regardless of
/// how many `Photo` rows ended up in the list.
private struct DateTarget: Identifiable {
    let id = UUID()
    let photos: [Photo]
}

/// Setting a capture date by hand — the only way this app can put one on a
/// photo at all. Import keeps only the bytes; the owner chose this over
/// asking for photo-library permission just to read a date off it.
///
/// `.graphical`, not the compact wheel: picking a day for a photo from months
/// back is exactly the case a full calendar gets to faster than scrolling
/// wheels one tick at a time.
private struct SetDateSheet: View {
    let photos: [Photo]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var date: Date
    // More than one target means Save writes a date onto every one of them
    // at once — reordering `All photos`, and, from "Sometime", collapsing a
    // whole undated section into a single day — with nothing in the app that
    // can put it back afterward. A single photo, from its own tile's context
    // menu, is one tap away from being changed right back, so that path still
    // saves immediately with no confirmation to click through.
    @State private var confirmingSave = false
    @State private var confirmingClear = false

    /// Whether clearing would change anything. Offering "Clear date" when
    /// every target is already undated is a button that always does
    /// nothing — the silent no-op this codebase already refuses to ship
    /// elsewhere (`PhotoPickerSheet`'s own toggle logic).
    private var hasExistingDate: Bool {
        photos.contains { $0.takenAt != nil }
    }

    init(photos: [Photo]) {
        self.photos = photos
        // Seeded from whichever day the group already has, so re-opening an
        // already-dated section doesn't silently reset it to today. An
        // undated section, or a photo that's never been dated, starts on
        // today as the least surprising guess to correct from.
        _date = State(initialValue: photos.first?.takenAt.map {
            SpecialDateSchedule.localDay(of: $0)
        } ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(selection: $date, displayedComponents: .date) {
                    Text("Date")
                }
                .datePickerStyle(.graphical)

                // `SyncApply.applyPhoto` already writes `takenAt`
                // unconditionally, nil included, so clearing replicates
                // correctly today — what was missing was anywhere in the app
                // that could *ask* for it. Before this, a photo that had ever
                // been dated could never be put back to undated again.
                if hasExistingDate {
                    Button(role: .destructive) {
                        if photos.count > 1 {
                            confirmingClear = true
                        } else {
                            clear()
                        }
                    } label: {
                        Text("Clear date")
                    }
                }
            }
            .navigationTitle(Text("Set date"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if photos.count > 1 {
                            confirmingSave = true
                        } else {
                            save()
                        }
                    }
                }
            }
            .confirmationDialog(Text("Set date for \(photos.count) photos?"),
                                isPresented: $confirmingSave, titleVisibility: .visible) {
                Button("Set date") { save() }
            }
            .confirmationDialog(Text("Clear date for \(photos.count) photos?"),
                                isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("Clear date", role: .destructive) { clear() }
            }
        }
    }

    private func save() {
        Haptics.tap()
        // Anchored the same way a Special Date is: noon UTC of the chosen
        // civil day, so the day `AlbumSections` groups it under agrees on
        // both phones no matter which timezone either is in when this saves
        // or later reads it back (`SpecialDateSchedule.anchor`).
        let anchor = SpecialDateSchedule.anchor(for: date)
        for photo in photos {
            photo.takenAt = anchor
            photo.updatedAt = .now
        }
        try? context.save()
        dismiss()
    }

    /// The other half of what `applyPhoto` already supported: putting a
    /// photo back to no date at all, the state every photo starts in before
    /// anyone sets one by hand.
    private func clear() {
        Haptics.tap()
        for photo in photos {
            photo.takenAt = nil
            photo.updatedAt = .now
        }
        try? context.save()
        dismiss()
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
