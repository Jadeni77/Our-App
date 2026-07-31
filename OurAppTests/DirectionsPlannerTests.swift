import Foundation
import Testing
@testable import OurApp

struct DirectionsPlannerTests {
    @Test func buildsGoogleMapsDrivingURL() {
        let url = DirectionsPlanner.googleMapsURL(latitude: 42.352, longitude: -71.064)
        #expect(url.absoluteString
                == "comgooglemaps://?daddr=42.352000,-71.064000&directionsmode=driving")
    }

    @Test func nearZeroCoordinatesStayDecimalNotExponential() {
        // "\(Double)" renders 5e-05 — a fixed format may not.
        let url = DirectionsPlanner.googleMapsURL(latitude: 0.00005, longitude: 0)
        #expect(url.absoluteString
                == "comgooglemaps://?daddr=0.000050,0.000000&directionsmode=driving")
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
