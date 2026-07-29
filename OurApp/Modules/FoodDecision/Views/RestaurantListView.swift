import SwiftUI
import UIKit

struct RestaurantListView: View {
    @State private var search: RestaurantSearch
    @Environment(\.openURL) private var openURL

    init(cuisine: Cuisine, provider: any RestaurantProvider = MapKitRestaurantProvider()) {
        _search = State(initialValue: RestaurantSearch(cuisine: cuisine, provider: provider))
    }

    var body: some View {
        Group {
            switch search.state {
            case .loading:
                ProgressView("Finding \(search.cuisine.name) near you…")
            case .loaded(let restaurants):
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(restaurants) { restaurant in
                            RestaurantCard(restaurant: restaurant)
                        }
                    }
                    .padding()
                }
            case .locationDenied:
                statusView(
                    emoji: "📍",
                    title: "We can't see where you are",
                    message: "Allow location access in Settings and we'll find \(search.cuisine.name) nearby."
                ) {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .noResults:
                statusView(
                    emoji: "🤷",
                    title: "Nothing nearby for \(search.cuisine.name)",
                    message: "Go back and try another cuisine — maybe re-roll?"
                ) {
                    EmptyView()
                }
            case .failed:
                statusView(
                    emoji: "😵",
                    title: "Search hiccuped",
                    message: "Check your connection and give it another go."
                ) {
                    Button("Retry") {
                        Task { await search.run() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("\(search.cuisine.emoji) \(search.cuisine.name)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await search.run() }
    }

    private func statusView(
        emoji: String,
        title: String,
        message: String,
        @ViewBuilder actions: () -> some View
    ) -> some View {
        VStack(spacing: 16) {
            Text(emoji).font(.system(size: 64))
            Text(title).font(.title3.bold())
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            actions()
        }
        .padding(32)
    }
}

#Preview {
    NavigationStack {
        RestaurantListView(cuisine: Cuisine(name: "Hotpot", emoji: "🍲"))
    }
}
