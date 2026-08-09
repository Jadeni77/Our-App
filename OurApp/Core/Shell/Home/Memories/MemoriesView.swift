import SwiftData
import SwiftUI

/// Hub sub-page: a timeline of moments, newest first.
///
/// Wears the sub-page chrome contract — dreamy background with no tilt parallax
/// and no moon (H16), hidden toolbar background, inline title, tab bar visible.
struct MemoriesView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: Memory.visible, sort: \Memory.day, order: .reverse)
    private var memories: [Memory]

    @State private var thumbnails = MemoryThumbnails()
    @State private var composing = false
    @State private var showing: Memory?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        ZStack {
            DreamyBackground(showsMoon: false)

            if memories.isEmpty {
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
            .task { if let first { thumbnails.loadIfNeeded(first) } }
            .accessibilityLabel(Text("Memory"))
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
