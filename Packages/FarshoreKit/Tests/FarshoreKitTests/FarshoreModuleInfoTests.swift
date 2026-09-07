import Foundation
import Testing
@testable import FarshoreKit

/// The package's face to whatever is hosting it. Deliberately tiny: everything
/// here has to be satisfiable by a standalone app that has never heard of
/// OurApp, which is why the orientation is our own enum and not the shell's.
struct FarshoreModuleInfoTests {
    @Test func theModuleIDIsStableAndLowercase() {
        #expect(FarshoreModuleInfo.id == "farshore")
    }

    @Test func itAsksForLandscape() {
        #expect(FarshoreModuleInfo.orientation == .landscape)
    }

    @Test func theTitleResolvesFromThePackageBundle() {
        var resource = FarshoreModuleInfo.title
        resource.locale = Locale(identifier: "en")
        let english = String(localized: resource)
        #expect(english == "Farshore")
        #expect(english.isEmpty == false)
    }
}
