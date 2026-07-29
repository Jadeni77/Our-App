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
