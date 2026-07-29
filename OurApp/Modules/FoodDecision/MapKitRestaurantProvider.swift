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
            let name = item.name.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Unnamed spot")
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

    /// F7 term ordering: where you stand determines how POIs are tagged.
    /// Stable partition — original order preserved within each group.
    static func orderedTerms(for cuisine: Cuisine, chineseSpeakingRegion: Bool) -> [String] {
        let (cjk, latin) = cuisine.searchTerms.reduce(into: ([String](), [String]())) { result, term in
            if term.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) {
                result.0.append(term)
            } else {
                result.1.append(term)
            }
        }
        return chineseSpeakingRegion ? cjk + latin : latin + cjk
    }

    /// F7 merge: batches arrive in term-priority order; dedupe by
    /// case-insensitive name + ~11m coordinate cell, distance-sort, cap.
    static func merge(_ batches: [[Restaurant]], limit: Int = 8) -> [Restaurant] {
        var seen = Set<String>()
        var unique: [Restaurant] = []
        for restaurant in batches.flatMap({ $0 }) {
            let key = "\(restaurant.name.lowercased())|\(String(format: "%.4f", restaurant.latitude))|\(String(format: "%.4f", restaurant.longitude))"
            if seen.insert(key).inserted {
                unique.append(restaurant)
            }
        }
        return Array(unique.sorted { $0.distanceMeters < $1.distanceMeters }.prefix(limit))
    }
}

extension MapKitRestaurantProvider: RestaurantProvider {
    /// F7: sequential multi-term search with early exit (open question resolved
    /// 2026-07-29). Region fit comes from where the user actually stands
    /// (reverse-geocoded country), falling back to the device locale — device
    /// language alone breaks when traveling.
    @MainActor
    func search(for cuisine: Cuisine) async throws -> [Restaurant] {
        let fetcher = LocationFetcher()
        let userLocation = try await fetcher.currentLocation()

        let chineseSpeaking = await Self.isChineseSpeakingRegion(around: userLocation)
        let terms = Self.orderedTerms(for: cuisine, chineseSpeakingRegion: chineseSpeaking)

        var batches: [[Restaurant]] = []
        var sawError: Error?
        for term in terms {
            do {
                batches.append(try await results(for: term, near: userLocation))
            } catch {
                sawError = error // a term can fail while another succeeds — fail soft
            }
            if Self.merge(batches).count >= 8 { break } // early exit at the cap
        }

        let merged = Self.merge(batches)
        if merged.isEmpty {
            if sawError != nil { throw RestaurantSearchError.searchFailed }
            throw RestaurantSearchError.noResults
        }
        return merged
    }

    private func results(for term: String, near userLocation: CLLocation) async throws -> [Restaurant] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = term
        request.resultTypes = .pointOfInterest
        // Food-adjacent categories so cafe/bakery/market-tagged cuisines
        // don't false-negative (final-review ruling, v1).
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket,
        ])
        request.region = MKCoordinateRegion(
            center: userLocation.coordinate,
            latitudinalMeters: 5_000,
            longitudinalMeters: 5_000
        )
        do {
            let response = try await MKLocalSearch(request: request).start()
            return Self.restaurants(from: response.mapItems, userLocation: userLocation, limit: 8)
        } catch {
            if let mkError = error as? MKError, mkError.code == .placemarkNotFound {
                return [] // this term found nothing; keep trying the others
            }
            throw RestaurantSearchError.searchFailed
        }
    }

    private static let chineseSpeakingCountries: Set<String> = ["CN", "TW", "HK", "MO", "SG"]

    /// Reverse-geocode the country the user is standing in; fall back to the
    /// device region if geocoding fails (offline, rate-limited).
    private static func isChineseSpeakingRegion(around location: CLLocation) async -> Bool {
        if let country = try? await CLGeocoder().reverseGeocodeLocation(location)
            .first?.isoCountryCode {
            return chineseSpeakingCountries.contains(country)
        }
        let fallback = Locale.current.region?.identifier ?? ""
        return chineseSpeakingCountries.contains(fallback)
    }
}
