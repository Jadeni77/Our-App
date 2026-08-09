import PhotosUI
import SwiftData
import SwiftUI

/// Picking photos, writing the note, choosing the day.
///
/// `PhotosPicker` runs out-of-process, so no photo-library permission or
/// `Info.plist` key is needed — non-obvious but true, and the same reason
/// `CoupleSettingsSheet` can pick avatars without one.
struct MemoryComposeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(CoupleIdentityStore.self) private var identity

    @State private var picked: [PhotosPickerItem] = []
    @State private var previews: [UIImage] = []
    @State private var pending: [Data] = []
    @State private var note = ""
    @State private var day = Date.now
    @State private var saving = false

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
                    Button { dismiss() } label: { Text("Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Text("Save") }
                        // At least one photo: a memory with none is a diary
                        // entry, which is Daily Question's job.
                        .disabled(pending.isEmpty || saving)
                }
            }
            .onChange(of: picked) { _, items in
                Task { await load(items) }
            }
        }
    }

    /// Loads the picked items once, up front, so Save is a synchronous write
    /// rather than an async one the user can dismiss out from under.
    private func load(_ items: [PhotosPickerItem]) async {
        var data: [Data] = []
        var images: [UIImage] = []
        for item in items.prefix(Memory.maxPhotos) {
            guard let bytes = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: bytes) else { continue }
            data.append(bytes)
            images.append(image)
        }
        pending = data
        previews = images
    }

    private func save() {
        guard let me = identity.me, !pending.isEmpty else { return }
        saving = true

        var ids: [String] = []
        for bytes in pending {
            // A photo that fails to encode is skipped rather than aborting the
            // whole memory — fail soft (principle 7).
            if let id = try? store.save(bytes) { ids.append(id) }
        }
        guard !ids.isEmpty else { saving = false; return }

        context.insert(Memory(note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                              day: day,
                              authorID: me.rawValue,
                              photoIDs: ids))
        try? context.save()
        Haptics.success()
        dismiss()
    }
}
