import Testing
@testable import OurApp

struct MoonshotScoringTests {
    @Test func failedLevelScoresZero() {
        #expect(MoonshotScoring.stars(cleared: false, flingsUsed: 1, par: 3) == 0)
    }

    @Test func atOrUnderParIsThree() {
        #expect(MoonshotScoring.stars(cleared: true, flingsUsed: 3, par: 3) == 3)
        #expect(MoonshotScoring.stars(cleared: true, flingsUsed: 1, par: 3) == 3)
    }

    @Test func parPlusOneIsTwo() {
        #expect(MoonshotScoring.stars(cleared: true, flingsUsed: 4, par: 3) == 2)
    }

    @Test func anythingSlowerIsOne() {
        #expect(MoonshotScoring.stars(cleared: true, flingsUsed: 9, par: 3) == 1)
    }
}
