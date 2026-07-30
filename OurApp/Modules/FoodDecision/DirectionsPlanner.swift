import Foundation

/// Where the Directions button hands off (F8): Google Maps when it's on the
/// phone, Apple Maps otherwise. This is only the *handoff* — restaurant
/// search itself stays MapKit (F3).
enum DirectionsPlanner {
    /// Google Maps' documented URL scheme for driving directions to a
    /// coordinate. Coordinates, not the name: the name re-runs as a search
    /// and can land on a different branch of the same restaurant.
    static func googleMapsURL(latitude: Double, longitude: Double) -> URL {
        // Interpolated doubles only produce URL-safe characters, so this
        // string always parses.
        URL(string: "comgooglemaps://?daddr=\(latitude),\(longitude)&directionsmode=driving")!
    }
}
