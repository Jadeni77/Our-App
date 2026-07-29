import SwiftUI

struct DecideView: View {
    let flow: FoodDecisionFlow
    let cuisine: Cuisine
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 32) {
            Text("How about…")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 48)
            Spacer()
            VStack(spacing: 16) {
                Text(cuisine.emoji).font(.system(size: 96))
                Text(cuisine.displayName)
                    .font(Theme.display(44))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
            }
            .id(cuisine) // new identity per proposal so re-rolls animate
            .transition(.scale.combined(with: .opacity))
            .padding(28)
            .glassCard(cornerRadius: 28)
            Spacer()
            Text("Hand the phone over 📱")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
            VStack(spacing: 12) {
                Button {
                    Haptics.success()
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
                    Haptics.tap()
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
        .background(Theme.duskGradient.ignoresSafeArea())
        .tint(Theme.rose)
    }
}

#Preview {
    DecideView(flow: FoodDecisionFlow(), cuisine: CuisinePool.all.first ?? .custom("Hotpot"))
}
