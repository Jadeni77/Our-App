import Testing
@testable import OurApp

@MainActor
struct ModuleDescriptorTests {
    @Test func foodDecisionExposesItsTile() {
        let descriptor = FoodDecisionModule.descriptor
        #expect(descriptor.id == "food-decision")
        #expect(descriptor.emoji == "🍽️")
        #expect(String(localized: descriptor.name) == "What should we eat?")
    }
}
