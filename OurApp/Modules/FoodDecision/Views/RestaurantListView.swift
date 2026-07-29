import SwiftUI
import UIKit

struct RestaurantListView: View {
    @State private var search: RestaurantSearch
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale

    init(cuisine: Cuisine, provider: any RestaurantProvider = MapKitRestaurantProvider()) {
        _search = State(initialValue: RestaurantSearch(cuisine: cuisine, provider: provider))
    }

    var body: some View {
        Group {
            switch search.state {
            case .loading:
                ProgressView("Finding \(search.cuisine.name(for: locale)) near you…")
                    .tint(.white)
                    .foregroundStyle(.white)
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
                    message: "Allow location access in Settings and we'll find \(search.cuisine.name(for: locale)) nearby."
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
                    title: "Nothing nearby for \(search.cuisine.name(for: locale))",
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
        .background(Theme.duskGradient.ignoresSafeArea())
        .tint(Theme.rose)
        .navigationTitle(Text(verbatim: "\(search.cuisine.emoji) \(search.cuisine.name(for: locale))"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await search.run() }
    }

    private func statusView(
        emoji: String,
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        @ViewBuilder actions: () -> some View
    ) -> some View {
        VStack(spacing: 16) {
            Text(emoji).font(.system(size: 64))
            Text(title).font(.title3.bold()).foregroundStyle(.white)
            Text(message)
                .font(.body)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            actions()
        }
        .padding(32)
    }
}

#Preview {
    NavigationStack {
        RestaurantListView(cuisine: CuisinePool.all.first ?? .custom("Hotpot"))
    }
}
