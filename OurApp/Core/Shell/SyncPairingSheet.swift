import SwiftUI

/// Pairing, once. One phone shows a code, the other types it.
///
/// Both phones show their own code and offer a field, so it doesn't matter who
/// starts — whoever types first is the one that pairs.
struct SyncPairingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var myCode = ""
    @State private var typed = ""
    @State private var failed = false
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: spaced(myCode))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                } header: {
                    Text("Your code")
                } footer: {
                    Text("Type this on the other phone. It works for two minutes.")
                }

                Section {
                    TextField(text: $typed) {
                        Text("Their code")
                    }
                    .keyboardType(.numberPad)
                    .font(.system(.title3, design: .rounded).monospacedDigit())
                    .onChange(of: typed) { _, entered in
                        failed = false
                        guard entered.count == SyncPairing.codeLength else { return }
                        Task { await attempt(entered) }
                    }
                    if working { ProgressView() }
                    if failed {
                        // One message for every refusal: wrong code, expired,
                        // phone not there. Naming which would tell a guesser
                        // what to change.
                        Text("That didn't work. Check the code and that both phones are on the same wi-fi.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Or enter theirs")
                }
            }
            .navigationTitle(Text("Pair our phones"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { Task { await cancel() } } label: { Text("Cancel") }
                }
            }
        }
        .task {
            myCode = await SyncStack.peers.beginPairing()
        }
    }

    /// `123 456` — easier to read aloud across a room, which is how this is
    /// actually going to be used.
    private func spaced(_ code: String) -> String {
        guard code.count == 6 else { return code }
        let middle = code.index(code.startIndex, offsetBy: 3)
        return "\(code[code.startIndex..<middle]) \(code[middle...])"
    }

    private func attempt(_ code: String) async {
        working = true
        let paired = await SyncStack.peers.pair(withCode: code)
        working = false
        if paired {
            Haptics.success()
            await SyncStack.peers.cancelPairing()
            dismiss()
        } else {
            failed = true
            typed = ""
        }
    }

    private func cancel() async {
        await SyncStack.peers.cancelPairing()
        dismiss()
    }
}
