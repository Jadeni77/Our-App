import Foundation
import Testing
@testable import OurApp

struct DirectionsPlannerTests {
    @Test func buildsGoogleMapsDrivingURL() {
        let url = DirectionsPlanner.googleMapsURL(latitude: 42.352, longitude: -71.064)
        #expect(url.absoluteString
                == "comgooglemaps://?daddr=42.352,-71.064&directionsmode=driving")
    }

    @Test func keepsFullCoordinatePrecision() {
        let url = DirectionsPlanner.googleMapsURL(latitude: 42.3521234, longitude: 121.5)
        #expect(url.absoluteString
                == "comgooglemaps://?daddr=42.3521234,121.5&directionsmode=driving")
    }

    /// `canOpenURL` silently answers false for undeclared schemes, which
    /// would turn "Google Maps first" into "Apple Maps always" with no error
    /// anywhere — so the declaration is part of the feature's contract.
    @Test func googleMapsSchemeIsDeclaredForCanOpenURL() {
        let declared = Bundle.main
            .object(forInfoDictionaryKey: "LSApplicationQueriesSchemes") as? [String]
        #expect(declared?.contains("comgooglemaps") == true)
    }
}
