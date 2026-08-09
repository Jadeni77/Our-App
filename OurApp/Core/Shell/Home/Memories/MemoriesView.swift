import SwiftData
import SwiftUI

/// Hub sub-page: a timeline of moments, newest first.
///
/// Wears the sub-page chrome contract — dreamy background with no tilt parallax
/// and no moon (H16), hidden toolbar background, inline title, tab bar visible.
struct MemoriesView: View {
    @Environment(CoupleIdentityStore.self) private var identity
    // `day` is anchored to noon UTC, so every memory from the same civil day —
    // a trip, typically — ties exactly. Without the tiebreak their order is
    // whatever the store returns, and can differ between launches.
    @Query(filter: Memory.visible,
           sort: [SortDescriptor(\Memory.day, order: .reverse),
                  SortDescriptor(\Memory.updatedAt, order: .reverse)])
    private var memories: [Memory]

    @State private var thumbnails = MemoryThumbnails()
    @State private var composing = false
    @State private var showing: Memory?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        ZStack {
            DreamyBackground(showsMoon: false)

            if identity.me == nil {
                // Same fail-soft as Daily Question (H19): an unattributed
                // memory can't be merged when sync lands, and a Save that
                // silently does nothing is a dead end (principle 7).
                whoIsThis
            } else if memories.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .navigationTitle(Text("Memories"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap()
                    composing = true
                } label: {
                    Image(systemName: "plus").foregroundStyle(.white)
                }
                .disabled(identity.me == nil)
                .accessibilityLabel(Text("Add a memory"))
            }
        }
        .sheet(isPresented: $composing) {
            MemoryComposeSheet()
        }
        .sheet(item: $showing) { memory in
            MemoryDetailView(memory: memory)
        }
    }

    private var whoIsThis: some View {
        VStack(spacing: 14) {
            Text(verbatim: "📷").font(.system(size: 38))
            Text("Tell us who this phone belongs to first")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(memories) { memory in
                    Button {
                        Haptics.tap()
                        showing = memory
                    } label: {
                        cell(memory)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
        }
    }

    private func cell(_ memory: Memory) -> some View {
        let first = memory.photoIDs.first
        return Color.white.opacity(0.12)
            .aspectRatio(1, contentMode: .fill)
            .overlay {
                if let first, let image = thumbnails.image(for: first) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    // A lost or not-yet-loaded file is a soft placeholder.
                    Image(systemName: "photo")
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .clipped()
            .overlay(alignment: .topTrailing) {
                if memory.photoIDs.count > 1 {
                    Text(verbatim: "\(memory.photoIDs.count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.35)))
                        .padding(5)
                }
            }
            .task { if let first { await thumbnails.loadIfNeeded(first) } }
            .accessibilityElement()
            .accessibilityLabel(label(for: memory))
    }

    /// Every cell reading "Memory" makes the grid unnavigable by screen
    /// reader. Compose the day, the note and the count instead.
    private func label(for memory: Memory) -> Text {
        let day = SpecialDateSchedule.localDay(of: memory.day)
            .formatted(.dateTime.year().month(.abbreviated).day())
        if memory.note.isEmpty {
            return Text(verbatim: day)
        }
        return Text(verbatim: "\(day), \(memory.note)")
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text(verbatim: "📷").font(.system(size: 40))
            Text("No memories yet — keep the first one")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
            Button {
                Haptics.tap()
                composing = true
            } label: {
                Text("Add a memory")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
            }
            .glassCard(cornerRadius: 22)
        }
        .padding(32)
    }
}

#Preview {
    NavigationStack { MemoriesView() }
        .environment(CoupleIdentityStore())
        .modelContainer(try! Persistence.makeContainer(inMemory: true))
}
