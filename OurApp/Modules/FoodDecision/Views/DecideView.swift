import SwiftUI

struct DecideView: View {
    let flow: FoodDecisionFlow
    let cuisine: Cuisine
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 32) {
            Text("How about…")
                .font(.title2)
                .foregroundStyle(.secondary)
                .padding(.top, 48)
            Spacer()
            VStack(spacing: 16) {
                Text(cuisine.emoji).font(.system(size: 96))
                Text(cuisine.name)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
            }
            .id(cuisine) // new identity per proposal so re-rolls animate
            .transition(.scale.combined(with: .opacity))
            Spacer()
            Text("Hand the phone over 📱")
                .font(.footnote)
                .foregroundStyle(.secondary)
            VStack(spacing: 12) {
                Button {
                    flow.agree(in: modelContext)
                } label: {
                    Label("Agree", systemImage: "checkmark")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)

                Button {
                    flow.reroll()
                } label: {
                    Label("Re-roll", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
    }
}

#Preview {
    DecideView(flow: FoodDecisionFlow(), cuisine: Cuisine(name: "Hotpot", emoji: "🍲"))
}
