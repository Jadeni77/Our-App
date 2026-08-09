import SwiftData
import SwiftUI

/// Date only — no title, no emoji, no repeat toggle, no delete (P17). An
/// anniversary always repeats yearly, is never deleted, and its name is
/// localized rather than stored, so there is nothing else to edit.
struct AnniversaryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// nil when no anniversary has been set yet.
    let existing: SpecialDate?

    @State private var date: Date

    init(existing: SpecialDate?) {
        self.existing = existing
        _date = State(initialValue: existing.map {
            SpecialDateSchedule.localDay(of: $0.date)
        } ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // A couple cannot have started in the future, and the day
                    // counter would go negative.
                    DatePicker(selection: $date, in: ...Date.now,
                               displayedComponents: .date) {
                        Text("The day we started")
                    }
                }
            }
            .navigationTitle(Text("Our anniversary"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Text("Save") }
                }
            }
        }
    }

    private func save() {
        let anchor = SpecialDateSchedule.anchor(for: date)
        if let existing {
            existing.date = anchor
            existing.updatedAt = .now
            Haptics.tap()
        } else {
            context.insert(SpecialDate(title: "", date: anchor,
                                       repeatsYearly: true, isAnniversary: true))
            Haptics.success()
        }
        try? context.save()
        dismiss()
    }
}

#Preview {
    AnniversaryEditorSheet(existing: nil)
        .modelContainer(try! Persistence.makeContainer(inMemory: true))
}
