import Testing
import Foundation
@testable import OurApp

private struct MockProvider: RestaurantProvider {
    let result: Result<[Restaurant], Error>
    func search(for cuisine: Cuisine) async throws -> [Restaurant] {
        try result.get()
    }
}

@MainActor
struct RestaurantSearchTests {
    private let cuisine = CuisinePool.all.first ?? .custom("Hotpot")
    private let sample = [
        Restaurant(
            id: UUID(), name: "Haidilao", distanceMeters: 320,
            address: "1 Main St", phone: nil, latitude: 42.34, longitude: -71.08
        ),
    ]

    @Test func successLoadsRestaurants() async {
        let search = RestaurantSearch(cuisine: cuisine, provider: MockProvider(result: .success(sample)))
        await search.run()
        #expect(search.state == .loaded(sample))
    }

    @Test func locationDeniedMapsToDeniedState() async {
        let search = RestaurantSearch(
            cuisine: cuisine,
            provider: MockProvider(result: .failure(RestaurantSearchError.locationDenied))
        )
        await search.run()
        #expect(search.state == .locationDenied)
    }

    @Test func noResultsMapsToNoResultsState() async {
        let search = RestaurantSearch(
            cuisine: cuisine,
            provider: MockProvider(result: .failure(RestaurantSearchError.noResults))
        )
        await search.run()
        #expect(search.state == .noResults)
    }

    @Test func unexpectedErrorsMapToFailedState() async {
        let search = RestaurantSearch(
            cuisine: cuisine,
            provider: MockProvider(result: .failure(URLError(.notConnectedToInternet)))
        )
        await search.run()
        #expect(search.state == .failed)
    }
}
