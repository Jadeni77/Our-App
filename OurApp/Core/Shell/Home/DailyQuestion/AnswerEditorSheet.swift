import SwiftUI

/// Writing or editing today's answer. Only today's is editable — a past answer
/// is what you thought that day, which is the point of keeping it.
struct AnswerEditorSheet: View {
    let question: DailyQuestion
    @State private var text: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    init(question: DailyQuestion, existing: String, onSave: @escaping (String) -> Void) {
        self.question = question
        self.onSave = onSave
        _text = State(initialValue: existing)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text: $text, axis: .vertical) {
                        Text("Tap to answer")
                    }
                    .lineLimit(4...12)
                } header: {
                    Text(question.text)
                }
            }
            .navigationTitle(Text("Your answer"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Haptics.success()
                        onSave(trimmed)
                        dismiss()
                    } label: { Text("Save") }
                        .disabled(trimmed.isEmpty)
                }
            }
        }
    }
}

#Preview {
    AnswerEditorSheet(question: DailyQuestionCatalog.all[0], existing: "") { _ in }
}
