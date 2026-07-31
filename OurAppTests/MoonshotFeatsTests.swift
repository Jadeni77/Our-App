import Testing
@testable import OurApp

struct MoonshotFeatsTests {
    @Test func featsDetectIndependently() {
        let all = FeatDetector.feats(flingsUsed: 1, usedAnyAbility: false,
                                     destructiblePieces: 4, destroyedPieces: 4)
        #expect(all == [.oneFling, .noAbility, .cleanSweep])
        let none = FeatDetector.feats(flingsUsed: 3, usedAnyAbility: true,
                                      destructiblePieces: 4, destroyedPieces: 2)
        #expect(none.isEmpty)
    }

    @Test func cleanSweepNeedsDestructibles() {
        #expect(!FeatDetector.feats(flingsUsed: 2, usedAnyAbility: true,
                                    destructiblePieces: 0, destroyedPieces: 0).contains(.cleanSweep))
    }
}
