import SwiftUI

struct DecidedView: View {
    let flow: FoodDecisionFlow
    let cuisine: Cuisine
    @State private var celebrate = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            VStack(spacing: 16) {
                Text(cuisine.emoji)
                    .font(.system(size: 96))
                    .scaleEffect(celebrate ? 1 : 0.3)
                Text("\(cuisine.displayName) it is! 🎉")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
            }
            Spacer()
            VStack(spacing: 12) {
                NavigationLink {
                    RestaurantListView(cuisine: cuisine)
                } label: {
                    Label("Find places near us", systemImage: "location.fill")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Start over") {
                    flow.startOver()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .background(Theme.duskGradient.ignoresSafeArea())
        .tint(Theme.rose)
        .sensoryFeedback(.success, trigger: celebrate)
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.5)) {
                celebrate = true
            }
        }
    }
}

#Preview {
    NavigationStack {
        DecidedView(flow: FoodDecisionFlow(), cuisine: CuisinePool.all.first ?? .custom("Hotpot"))
    }
}
