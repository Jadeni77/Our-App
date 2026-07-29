import Foundation
import Testing
@testable import OurApp

@MainActor
struct ModuleDescriptorTests {
    @Test func foodDecisionExposesItsTile() {
        let descriptor = FoodDecisionModule.descriptor
        #expect(descriptor.id == "food-decision")
        #expect(descriptor.emoji == "🍽️")
        // Pin the resolution locale: the test host may run in any of the app's
        // three languages (device setting, per-app setting, or a persisted
        // -AppleLanguages from a past launch), and this must not flake.
        var name = descriptor.name
        name.locale = Locale(identifier: "en")
        #expect(String(localized: name) == "What should we eat?")
    }

    @Test func foodDecisionEntryViewIsBuildable() {
        _ = FoodDecisionModule.descriptor.makeEntryView()
    }
}
