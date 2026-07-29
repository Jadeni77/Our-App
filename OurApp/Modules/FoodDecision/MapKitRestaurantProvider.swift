import Foundation
import MapKit

/// MapKit-backed implementation of `RestaurantProvider` (decision F3: free,
/// native, no API key). Task 6 adds the live `search`; the mapping below is
/// pure and unit-tested.
struct MapKitRestaurantProvider {
    /// Converts raw MapKit results into distance-sorted, capped `Restaurant`s.
    static func restaurants(
        from mapItems: [MKMapItem],
        userLocation: CLLocation,
        limit: Int = 8
    ) -> [Restaurant] {
        let mapped = mapItems.map { item in
            let coordinate = item.placemark.coordinate
            let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .distance(from: userLocation)
            // MapKit synthesizes a name (e.g., "Unknown Location") for coordinate-only items.
            // The nil branch is defensive; the realistic path is non-empty name check.
            let name = item.name.flatMap { $0.isEmpty ? nil : $0 } ?? "Unnamed spot"
            return Restaurant(
                id: UUID(),
                name: name,
                distanceMeters: distance,
                address: item.placemark.title,
                phone: item.phoneNumber,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        }
        return Array(mapped.sorted { $0.distanceMeters < $1.distanceMeters }.prefix(limit))
    }
}

extension MapKitRestaurantProvider: RestaurantProvider {
    /// Fixed ~5 km region, capped at 8 results (open question resolved for v1;
    /// adaptive radius deferred until real use demands it).
    /// @MainActor matches the protocol requirement — without it this witness is
    /// nonisolated and calling the @MainActor `LocationFetcher()` init won't compile.
    @MainActor
    func search(cuisine: String) async throws -> [Restaurant] {
        let fetcher = LocationFetcher()
        let userLocation = try await fetcher.currentLocation()

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = cuisine
        request.resultTypes = .pointOfInterest
        // Food-adjacent categories included so pool entries like Brunch, Banh Mi,
        // and Dim Sum (tagged cafe/bakery/market by MapKit) don't false-negative.
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket,
        ])
        request.region = MKCoordinateRegion(
            center: userLocation.coordinate,
            latitudinalMeters: 5_000,
            longitudinalMeters: 5_000
        )

        let response: MKLocalSearch.Response
        do {
            response = try await MKLocalSearch(request: request).start()
        } catch {
            // MKLocalSearch reports "no results" as an MKError; treat anything
            // else as a plain failure the UI can offer a retry for.
            if let mkError = error as? MKError, mkError.code == .placemarkNotFound {
                throw RestaurantSearchError.noResults
            }
            throw RestaurantSearchError.searchFailed
        }

        let restaurants = Self.restaurants(from: response.mapItems, userLocation: userLocation)
        guard !restaurants.isEmpty else { throw RestaurantSearchError.noResults }
        return restaurants
    }
}
