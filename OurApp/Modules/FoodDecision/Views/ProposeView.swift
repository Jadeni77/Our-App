import SwiftUI

struct ProposeView: View {
    let flow: FoodDecisionFlow
    @State private var manualEntry = ""

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            VStack(spacing: 12) {
                Text("🍽️").font(.system(size: 72))
                Text("What should we eat?")
                    .font(.largeTitle.bold())
                Text("Draw a cuisine, or type a craving.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 16) {
                Button {
                    flow.proposeRandom()
                } label: {
                    Label("Surprise us", systemImage: "dice.fill")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                HStack {
                    TextField("Or type a cuisine…", text: $manualEntry)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.go)
                        .onSubmit(submitManual)
                    Button("Go", action: submitManual)
                        .buttonStyle(.bordered)
                        .disabled(manualEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
    }

    private func submitManual() {
        flow.proposeManual(manualEntry)
        manualEntry = ""
    }
}

#Preview {
    ProposeView(flow: FoodDecisionFlow())
}
