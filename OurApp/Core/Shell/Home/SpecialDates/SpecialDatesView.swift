import SwiftData
import SwiftUI

/// The first hub sub-page (P16): the dates we don't want to miss, soonest
/// first. Pushed from Home, so it wears the sub-page chrome contract —
/// dreamy background with no tilt parallax, hidden toolbar background, inline
/// title, tab bar left visible.
struct SpecialDatesView: View {
    @Environment(\.modelContext) private var context
    /// Tombstoned rows never reach the UI.
    @Query(filter: SpecialDate.visible) private var dates: [SpecialDate]

    @State private var editing: SpecialDate?
    @State private var addingNew = false

    var body: some View {
        let split = SpecialDateSchedule.ordered(dates)

        ZStack {
            // No tilt parallax: motion sensors stay Home-only.
            DreamyBackground()

            if dates.isEmpty {
                emptyState
            } else {
                list(comingUp: split.comingUp, passed: split.passed)
            }
        }
        .navigationTitle(Text("Special Dates"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap()
                    addingNew = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(.white)
                }
                .accessibilityLabel(Text("Add a date"))
            }
        }
        .sheet(isPresented: $addingNew) {
            SpecialDateEditorSheet(existing: nil)
        }
        .sheet(item: $editing) { date in
            SpecialDateEditorSheet(existing: date)
        }
    }

    private func list(comingUp: [SpecialDateSchedule.Entry],
                      passed: [SpecialDateSchedule.Entry]) -> some View {
        List {
            // A section with nothing in it would render a bare header.
            if !comingUp.isEmpty {
                section(header: "Coming up", entries: comingUp)
            }
            if !passed.isEmpty {
                section(header: "Passed", entries: passed)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func section(header: LocalizedStringKey,
                         entries: [SpecialDateSchedule.Entry]) -> some View {
        Section {
            // The status came back from `ordered` — rows never recompute it.
            ForEach(entries, id: \.date.id) { entry in
                let date = entry.date
                Button {
                    Haptics.tap()
                    editing = date
                } label: {
                    SpecialDateRow(date: date, status: entry.status)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        softDelete(date)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text(header)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(.white.opacity(0.75))
                .textCase(.uppercase)
        }
        .listRowBackground(Color.clear)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            // Verbatim: it's decoration, not copy. A literal Text("💗") is a
            // localizable key, so the build extracts it into the catalog as a
            // string someone is expected to translate.
            Text(verbatim: "💗").font(.system(size: 40))
            Text("No dates yet — add the ones we don't want to miss")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
            Button {
                Haptics.tap()
                addingNew = true
            } label: {
                Text("Add a date")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
            }
            .glassCard(cornerRadius: 22)
        }
        .padding(32)
    }

    /// Delete is a tombstone, never a removal (DESIGN.md §7 record hygiene).
    private func softDelete(_ date: SpecialDate) {
        Haptics.tap()
        date.deletedAt = .now
        date.updatedAt = .now
        try? context.save()
    }
}

#Preview {
    NavigationStack {
        SpecialDatesView()
    }
    .modelContainer(try! Persistence.makeContainer(inMemory: true))
}
