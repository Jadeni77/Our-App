import Foundation
import Testing
@testable import OurApp

/// Ids that two phones must agree on without talking to each other.
struct DerivedUUIDTests {
    /// **A golden value, deliberately hardcoded.** The point is not that some
    /// UUID comes out; it is that *this* one does, in every process, on every
    /// device, in every future version of the app. A derivation that changed
    /// would silently split every existing record in two.
    @Test func aKnownStringAlwaysDerivesTheSameID() {
        #expect(DerivedUUID.from("hello").uuidString == "2CF24DBA-5FB0-430E-A6E8-3B2AC5B9E29E")
    }

    @Test func differentStringsDeriveDifferentIDs() {
        #expect(DerivedUUID.from("a") != DerivedUUID.from("b"))
    }

    /// Well-formed enough that CloudKit and SwiftData treat it as a normal id.
    @Test func itLooksLikeAVersionFourUUID() {
        let text = DerivedUUID.from("anything").uuidString
        #expect(text.count == 36)
        #expect(Array(text)[14] == "4")
    }
}
