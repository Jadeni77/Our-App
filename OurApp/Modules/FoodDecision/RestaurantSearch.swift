import Foundation
import Observation

/// Drives one restaurant lookup and exposes a renderable state — every
/// failure degrades to a distinct, friendly state (fail-soft principle).
@MainActor
@Observable
final class RestaurantSearch {
    enum State: Equatable {
        case loading
        case loaded([Restaurant])
        case locationDenied
        case noResults
        case failed
    }

    private(set) var state: State = .loading
    let cuisine: Cuisine
    private let provider: any RestaurantProvider

    init(cuisine: Cuisine, provider: any RestaurantProvider = MapKitRestaurantProvider()) {
        self.cuisine = cuisine
        self.provider = provider
    }

    func run() async {
        state = .loading
        do {
            state = .loaded(try await provider.search(for: cuisine))
        } catch RestaurantSearchError.locationDenied {
            state = .locationDenied
        } catch RestaurantSearchError.noResults {
            state = .noResults
        } catch {
            state = .failed
        }
    }
}
