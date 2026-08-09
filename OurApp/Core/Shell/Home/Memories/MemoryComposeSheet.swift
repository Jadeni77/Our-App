import PhotosUI
import SwiftData
import SwiftUI

/// Picking photos, writing the note, choosing the day.
///
/// `PhotosPicker` runs out-of-process, so no photo-library permission or
/// `Info.plist` key is needed — non-obvious but true, and the same reason
/// `CoupleSettingsSheet` can pick avatars without one.
///
/// **Photos are downscaled and written as they are picked, off the main actor**,
/// and only their ids are held afterwards. Keeping the picked `Data` plus
/// decoded previews until Save meant nine 12-megapixel photos resident twice
/// over — hundreds of megabytes, and a realistic jetsam — and then eighteen
/// synchronous ImageIO encodes on the main thread when Save was tapped, with no
/// progress possible because the thread that would draw it was blocked.
struct MemoryComposeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(CoupleIdentityStore.self) private var identity

    @State private var picked: [PhotosPickerItem] = []
    /// Ids of files already written. Removed again if the sheet is cancelled.
    @State private var staged: [String] = []
    /// 400px thumbnails only — never the full decodes.
    @State private var previews: [UIImage] = []
    @State private var importing = false
    @State private var skipped = 0
    @State private var note = ""
    @State private var day = Date.now

    private let store = MemoryPhotoStore()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $picked,
                                 maxSelectionCount: Memory.maxPhotos,
                                 matching: .images) {
                        Label {
                            Text(previews.isEmpty ? "Choose photos" : "Change photos")
                        } icon: {
                            Image(systemName: "photo.on.rectangle")
                        }
                    }
                    .disabled(importing)

                    if importing {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Adding photos…")
                        }
                    }

                    if !previews.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(previews.enumerated()), id: \.offset) { _, image in
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 10,
                                                                    style: .continuous))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    // Fail soft, but not silently: a photo that couldn't be read
                    // should say so rather than just not appear.
                    if skipped > 0 {
                        Text("\(skipped) photos couldn't be added")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    TextField(text: $note, axis: .vertical) {
                        Text("What happened?")
                    }
                    .lineLimit(2...6)
                } header: {
                    Text("Note")
                }

                Section {
                    DatePicker(selection: $day, in: ...Date.now,
                               displayedComponents: .date) {
                        Text("Date")
                    }
                }
            }
            .navigationTitle(Text("New memory"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { cancel() } label: { Text("Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Text("Save") }
                        // At least one photo: a memory with none is a diary
                        // entry, which is Daily Question's job.
                        .disabled(staged.isEmpty || importing)
                }
            }
            .onChange(of: picked) { _, items in
                Task { await stage(items) }
            }
        }
        .interactiveDismissDisabled(importing)
    }

    /// Writes each picked photo straight to disk, off the main actor, keeping
    /// only its id and a thumbnail. Replacing a selection discards whatever was
    /// staged before, so cancelling or re-picking never leaves files behind.
    private func stage(_ items: [PhotosPickerItem]) async {
        let previouslyStaged = staged
        importing = true
        staged = []
        previews = []
        skipped = 0

        let store = self.store
        for item in items.prefix(Memory.maxPhotos) {
            guard let bytes = try? await item.loadTransferable(type: Data.self) else {
                skipped += 1
                continue
            }
            let written = await Task.detached(priority: .userInitiated) { () -> String? in
                try? store.save(bytes)
            }.value
            guard let written else {
                skipped += 1
                continue
            }
            staged.append(written)
            if let thumbnail = store.thumbnail(for: written) { previews.append(thumbnail) }
        }

        for id in previouslyStaged { store.delete(id) }
        importing = false
    }

    private func cancel() {
        for id in staged { store.delete(id) }
        dismiss()
    }

    private func save() {
        guard let me = identity.me, !staged.isEmpty else { return }

        context.insert(Memory(note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                              day: day,
                              authorID: me.rawValue,
                              photoIDs: staged))
        do {
            try context.save()
        } catch {
            // The record didn't persist, so the files it named are orphans.
            for id in staged { store.delete(id) }
            return
        }
        Haptics.success()
        dismiss()
    }
}
