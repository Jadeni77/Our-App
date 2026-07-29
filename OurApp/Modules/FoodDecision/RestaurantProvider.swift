import Foundation

/// One nearby restaurant, already distance-annotated relative to the user.
/// Deliberately MapKit-free so the provider stays swappable (module contract).
struct Restaurant: Identifiable, Equatable {
    let id: UUID
    let name: String
    let distanceMeters: Double
    let address: String?
    let phone: String?
    let latitude: Double
    let longitude: Double
}

enum RestaurantSearchError: Error, Equatable {
    case locationDenied
    case noResults
    case searchFailed
}

/// The module's seam for restaurant lookup (decision F3 hides MapKit behind this).
/// @MainActor because search is always UI-triggered and the CoreLocation machinery
/// underneath wants main-thread affinity — this keeps implementations warning-free.
/// The provider owns the multi-term strategy (F7) — consuming the Cuisine struct
/// lets the implementation batch queries and order terms by region.
protocol RestaurantProvider {
    @MainActor func search(for cuisine: Cuisine) async throws -> [Restaurant]
}
