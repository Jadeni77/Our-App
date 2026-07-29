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

    private func restaurant(_ name: String, lat: Double, lon: Double, distance: Double) -> Restaurant {
        Restaurant(id: UUID(), name: name, distanceMeters: distance,
                   address: nil, phone: nil, latitude: lat, longitude: lon)
    }

    @Test func orderedTermsPutCJKFirstInChineseRegions() {
        let hotpot = CuisinePool.all.first { $0.id == "hotpot" }!
        let zhFirst = MapKitRestaurantProvider.orderedTerms(for: hotpot, chineseSpeakingRegion: true)
        #expect(zhFirst.first == "火锅")
        #expect(zhFirst.contains("hotpot"))
        let enFirst = MapKitRestaurantProvider.orderedTerms(for: hotpot, chineseSpeakingRegion: false)
        #expect(enFirst.first == "hotpot")
        #expect(Set(enFirst) == Set(zhFirst)) // same terms, different order
    }

    @Test func mergeDedupesAcrossBatchesByNameAndCoordinate() {
        let a = restaurant("Haidilao", lat: 42.34001, lon: -71.08001, distance: 300)
        let aDupe = restaurant("HAIDILAO", lat: 42.340012, lon: -71.080011, distance: 300)
        let b = restaurant("Little Sheep", lat: 42.35, lon: -71.09, distance: 800)
        let merged = MapKitRestaurantProvider.merge([[a], [aDupe, b]])
        #expect(merged.count == 2)
        #expect(merged.map(\.name) == ["Haidilao", "Little Sheep"]) // distance-sorted
    }

    @Test func mergeCapsAtTheLimit() {
        let many = (0..<12).map { restaurant("Spot \($0)", lat: 42.3, lon: -71.0, distance: Double(100 + $0)) }
            .enumerated().map { index, r in
                restaurant(r.name, lat: 42.3 + Double(index) * 0.01, lon: -71.0, distance: r.distanceMeters)
            }
        #expect(MapKitRestaurantProvider.merge([many]).count == 8)
    }
}
