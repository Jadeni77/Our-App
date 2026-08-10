import SwiftData
import SwiftUI

/// One memory, full size: its photos, the note, the day. Deleting from here
/// tombstones the record *and* removes the files — the one place a delete is
/// not purely a tombstone, because the file is a local cache of a synced
/// record rather than the record itself.
struct MemoryDetailView: View {
    let memory: Memory

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    private let store = MemoryPhotoStore()
    @State private var confirming = false

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showsMoon: false)

                ScrollView {
                    VStack(spacing: 14) {
                        TabView {
                            ForEach(memory.photoIDs, id: \.self) { id in
                                if let image = store.image(for: id) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                } else {
                                    Image(systemName: "photo")
                                        .font(.system(size: 40))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                            }
                        }
                        .tabViewStyle(.page)
                        .frame(height: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                        if !memory.note.isEmpty {
                            Text(memory.note)          // user data, verbatim
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // No date line at all when there isn't one — "Unknown"
                        // would be a label for something nobody asked about.
                        if let day = memory.day {
                            Text(verbatim: SpecialDateSchedule.localDay(of: day)
                                .formatted(.dateTime.year().month(.abbreviated).day()))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.65))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .confirmationDialog(Text("Delete this memory?"),
                                isPresented: $confirming, titleVisibility: .visible) {
                Button(role: .destructive) { delete() } label: { Text("Delete") }
            } message: {
                // Unlike every other delete in the app, this one destroys files.
                Text("Its photos are removed from the app. This can't be undone.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Done") }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) { confirming = true } label: { Text("Delete") }
                }
            }
        }
    }

    private func delete() {
        Haptics.tap()
        memory.deletedAt = .now
        memory.updatedAt = .now
        do {
            // Files go only once the tombstone is durable. Deleting first meant
            // a failed save — disk full, say, which is exactly when someone is
            // deleting things — left a visible memory whose photos were gone.
            try context.save()
        } catch {
            memory.deletedAt = nil
            return
        }
        for id in memory.photoIDs { store.delete(id) }
        dismiss()
    }
}
