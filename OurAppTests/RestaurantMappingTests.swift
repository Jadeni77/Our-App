import Testing
import MapKit
@testable import OurApp

struct RestaurantMappingTests {
    // Northeastern-ish Boston coordinates.
    private let userLocation = CLLocation(latitude: 42.3398, longitude: -71.0892)

    private func mapItem(name: String, latitude: Double, longitude: Double) -> MKMapItem {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        let item = MKMapItem(placemark: placemark)
        item.name = name
        return item
    }

    @Test func computesDistanceFromUserLocation() {
        // 0.01° of latitude ≈ 1112 m.
        let items = [mapItem(name: "Far Bowl", latitude: 42.3498, longitude: -71.0892)]
        let result = MapKitRestaurantProvider.restaurants(from: items, userLocation: userLocation)
        #expect(result.count == 1)
        #expect(abs(result[0].distanceMeters - 1112) < 25)
    }

    @Test func sortsByDistanceFromUser() {
        let items = [
            mapItem(name: "Far Bowl", latitude: 42.3598, longitude: -71.0892),
            mapItem(name: "Near Noodles", latitude: 42.3408, longitude: -71.0892),
        ]
        let result = MapKitRestaurantProvider.restaurants(from: items, userLocation: userLocation)
        #expect(result.map(\.name) == ["Near Noodles", "Far Bowl"])
    }

    @Test func capsResultsAtTheLimit() {
        let items = (0..<12).map { index in
            mapItem(name: "Spot \(index)", latitude: 42.3398 + Double(index) * 0.001, longitude: -71.0892)
        }
        let result = MapKitRestaurantProvider.restaurants(from: items, userLocation: userLocation)
        #expect(result.count == 8)
    }

    @Test func fallsBackToPlaceholderNameAndKeepsCoordinates() {
        let items = [mapItem(name: "", latitude: 42.3408, longitude: -71.0902)]
        let result = MapKitRestaurantProvider.restaurants(from: items, userLocation: userLocation)
        #expect(result[0].name == "Unnamed spot")
        #expect(abs(result[0].latitude - 42.3408) < 0.0001)
        #expect(abs(result[0].longitude - -71.0902) < 0.0001)
    }
}
