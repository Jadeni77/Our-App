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
    @State private var editingAnniversary = false

    var body: some View {
        let split = SpecialDateSchedule.ordered(dates)

        ZStack {
            // No tilt parallax: motion sensors stay Home-only.
            DreamyBackground()

            list(split)

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
        .sheet(isPresented: $editingAnniversary) {
            AnniversaryEditorSheet(existing: split.anniversary?.date)
        }
    }

    private func list(_ split: SpecialDateSchedule.Split) -> some View {
        List {
            Section {
                AnniversaryCard(entry: split.anniversary) {
                    Haptics.tap()
                    editingAnniversary = true
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 2, trailing: 12))
            }

            // A section with nothing in it would render a bare header.
            if split.comingUp.isEmpty && split.passed.isEmpty {
                noOtherDates
            } else {
                if !split.comingUp.isEmpty {
                    section(header: "Coming up", entries: split.comingUp,
                            anniversary: split.anniversary?.date)
                }
                if !split.passed.isEmpty {
                    section(header: "Passed", entries: split.passed,
                            anniversary: split.anniversary?.date)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var noOtherDates: some View {
        Text("No other dates yet — add the ones we don't want to miss")
            .font(.system(.footnote, design: .rounded))
            .foregroundStyle(.white.opacity(0.8))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private func section(header: LocalizedStringKey,
                         entries: [SpecialDateSchedule.Entry],
                         anniversary: SpecialDate?) -> some View {
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
                    // Every row here is deletable by construction: `ordered`
                    // hands the real anniversary back separately, so nothing in
                    // these sections is the one Home depends on. Even a stray
                    // second flagged row can be removed — which is the whole
                    // point of it falling back to being an ordinary date.
                    Button(role: .destructive) {
                        softDelete(date, anniversary: anniversary)
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

    /// Delete is a tombstone, never a removal (DESIGN.md §7 record hygiene).
    ///
    /// The guard is on the mutation rather than on the button, so a future call
    /// site inherits it instead of having to remember it. It compares identity,
    /// not the `isAnniversary` flag: a stray second flagged row is an ordinary
    /// date and must stay removable.
    private func softDelete(_ date: SpecialDate, anniversary: SpecialDate?) {
        guard date.id != anniversary?.id else { return }
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
