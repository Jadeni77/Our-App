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
                    .font(Theme.display(34))
                    .foregroundStyle(.white)
                Text("Draw a cuisine, or type a craving.")
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            VStack(spacing: 16) {
                Button {
                    Haptics.tap()
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
                        .textFieldStyle(.plain)
                        .foregroundStyle(.white)
                        .submitLabel(.go)
                        .onSubmit(submitManual)
                    Button("Go", action: submitManual)
                        .buttonStyle(.bordered)
                        .disabled(manualEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(12)
                .glassCard(cornerRadius: 20)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .background(Theme.duskGradient.ignoresSafeArea())
        .tint(Theme.rose)
    }

    private func submitManual() {
        flow.proposeManual(manualEntry)
        manualEntry = ""
    }
}

#Preview {
    ProposeView(flow: FoodDecisionFlow())
}
