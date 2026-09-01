import SwiftData
import SwiftUI

/// Hub sub-page: a timeline of moments, newest first.
///
/// Wears the sub-page chrome contract — dreamy background with no tilt parallax
/// and no moon (H16), hidden toolbar background, inline title, tab bar visible.
struct MemoriesView: View {
    // Sorted again by `MemoryTimeline`, which is where the real ordering rule
    // lives — undated memories can't be expressed as a sort descriptor, and a
    // descriptor can't be tested. This sort just keeps the input stable.
    @Query(filter: Memory.visible,
           sort: [SortDescriptor(\Memory.day, order: .reverse),
                  SortDescriptor(\Memory.updatedAt, order: .reverse)])
    private var memories: [Memory]

    @Environment(\.modelContext) var context
    private let thumbnails = MemoryThumbnails.shared
    @State private var composing = MemoriesView.opensComposerAtLaunch
    @State private var showing: Memory?

    /// Which half of the page is showing. Moments is the existing timeline;
    /// Albums is the grid of covers this task adds.
    enum Tab: String, CaseIterable, Identifiable {
        case moments, albums
        var id: String { rawValue }
        var label: LocalizedStringKey { self == .moments ? "Moments" : "Albums" }
    }

    @State private var tab: Tab = .moments

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    /// `-composeMemory` opens the sheet at launch, so headless screenshots can
    /// reach copy that otherwise needs a tap. Read once as initial state rather
    /// than in `onAppear`: a lifecycle modifier on a view that may not be there
    /// is how the Daily Question badge silently stopped installing (H18).
    private static var opensComposerAtLaunch: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-composeMemory")
        #else
        false
        #endif
    }

    var body: some View {
        ZStack {
            DreamyBackground(showsMoon: false)

            VStack(spacing: 0) {
                Picker(selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.label).tag($0) }
                } label: {
                    Text("View")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14)
                .padding(.top, 8)

                // A plain frame, not another ZStack: `grid` and `emptyState`
                // already know how to fill and center themselves respectively,
                // and this is the same contract they had before the picker
                // was added above them.
                Group {
                    if tab == .moments {
                        if memories.isEmpty {
                            emptyState
                        } else {
                            grid
                        }
                    } else {
                        AlbumsGridView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(Text("Memories"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            // Composing a memory only makes sense while looking at Moments —
            // Albums has its own trailing action for filing a new album, and
            // showing both at once would leave two "+" buttons pointing at
            // two different sheets.
            if tab == .moments {
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
        }
        .sheet(isPresented: $composing) {
            MemoryComposeSheet()
        }
        .sheet(item: $showing) { memory in
            MemoryDetailView(memory: memory)
        }
        // **Keyed on the count, not bare.** A plain `.task` runs once per
        // appearance and nothing else creates `Photo` rows —
        // `MemoryComposeSheet.save()` inserts only the `Memory` — so a memory
        // added just now, or one arriving from her phone while this page is
        // open, had no library rows until you left Memories and came back.
        // Add three photos, tap Save, switch to Albums, tap Add photos, and
        // they simply were not there.
        .task(id: memories.count) { PhotoLibrary.seed(in: context) }
    }

private var grid: some View {
        let timeline = MemoryTimeline.ordered(memories)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 3) {
                cells(timeline.dated)
                if !timeline.undated.isEmpty {
                    // Only ever shown when there is something under it, so a
                    // timeline where every day is known looks exactly as before.
                    Text("Sometime")
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.top, 16)
                        .padding(.leading, 4)
                    cells(timeline.undated)
                }
            }
            .padding(3)
        }
    }

    private func cells(_ list: [Memory]) -> some View {
        LazyVGrid(columns: columns, spacing: 3) {
            ForEach(list) { memory in
                Button {
                    Haptics.tap()
                    showing = memory
                } label: {
                    cell(memory)
                }
                .buttonStyle(.plain)
            }
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
        let day = memory.day.map {
            SpecialDateSchedule.localDay(of: $0)
                .formatted(.dateTime.year().month(.abbreviated).day())
        }
        switch (day, memory.note.isEmpty) {
        case let (day?, false): return Text(verbatim: "\(day), \(memory.note)")
        case let (day?, true): return Text(verbatim: day)
        case (nil, false): return Text(verbatim: memory.note)
        // Nothing to read out but the fact that it exists.
        case (nil, true): return Text("Undated memory")
        }
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
