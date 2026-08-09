import SwiftData
import SwiftUI

/// Add or edit one date. `existing == nil` means we're adding.
///
/// Deleting from here sets the tombstone, exactly like the list's swipe —
/// there is one delete rule in this feature, not two.
struct SpecialDateEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let existing: SpecialDate?

    @State private var title: String
    @State private var icon: DateIcon
    @State private var date: Date
    @State private var repeatsYearly: Bool

    init(existing: SpecialDate?) {
        self.existing = existing
        _title = State(initialValue: existing?.title ?? "")
        _icon = State(initialValue: existing?.icon ?? .heart)
        // Through `localDay`: the stored value is noon UTC, so seeding the
        // picker with it raw shows the following day anywhere past UTC+12 —
        // and then saving shifts the date by one.
        _date = State(initialValue: existing.map {
            SpecialDateSchedule.localDay(of: $0.date)
        } ?? .now)
        _repeatsYearly = State(initialValue: existing?.repeatsYearly ?? false)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text: $title) {
                        Text("What are we remembering?")
                    }
                } header: {
                    Text("Title")
                }

                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6),
                              spacing: 12) {
                        ForEach(DateIcon.allCases, id: \.self) { candidate in
                            Button {
                                Haptics.tap()
                                icon = candidate
                            } label: {
                                DateIconView(icon: candidate, size: 38)
                                    .overlay {
                                        if candidate == icon {
                                            RoundedRectangle(cornerRadius: 38 * 0.30,
                                                             style: .continuous)
                                                .strokeBorder(Theme.indigo, lineWidth: 3)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Icon"))
                            .accessibilityAddTraits(candidate == icon ? [.isSelected] : [])
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("Icon")
                }

                Section {
                    DatePicker(selection: $date, displayedComponents: .date) {
                        Text("Date")
                    }
                    Toggle(isOn: $repeatsYearly) {
                        Text("Repeats every year")
                    }
                }

                // Only ever opened for rows in the list, and `ordered` keeps
                // the real anniversary out of those, so anything reachable here
                // is deletable.
                if existing != nil {
                    Section {
                        Button(role: .destructive) {
                            delete()
                        } label: {
                            Text("Delete")
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? Text("New date") : Text("Edit date"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Text("Save") }
                        .disabled(trimmedTitle.isEmpty)
                }
            }
        }
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }
        // The picker hands back the day carrying whatever time-of-day it was
        // seeded with; store it at local noon so the day can't drift when the
        // phone changes timezone (see SpecialDateSchedule.anchor).
        let anchor = SpecialDateSchedule.anchor(for: date)
        if let existing {
            existing.title = trimmedTitle
            existing.icon = icon
            existing.date = anchor
            existing.repeatsYearly = repeatsYearly
            existing.updatedAt = .now
            Haptics.tap()
        } else {
            context.insert(SpecialDate(title: trimmedTitle, date: anchor,
                                       repeatsYearly: repeatsYearly, icon: icon))
            Haptics.success()
        }
        try? context.save()
        dismiss()
    }

    private func delete() {
        guard let existing else { return }
        Haptics.tap()
        existing.deletedAt = .now
        existing.updatedAt = .now
        try? context.save()
        dismiss()
    }
}

#Preview {
    SpecialDateEditorSheet(existing: nil)
        .modelContainer(try! Persistence.makeContainer(inMemory: true))
}
