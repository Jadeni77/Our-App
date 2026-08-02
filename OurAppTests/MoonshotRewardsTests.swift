import Foundation
import Testing
@testable import OurApp

struct MoonshotRewardsTests {
    private let levelA = UUID(), levelB = UUID()

    private func solo(_ p: String, _ l: UUID, _ stars: Int) -> LevelResultSnapshot {
        .init(partnerID: p, levelID: l, mode: .solo, cleared: stars > 0, bestStars: stars)
    }

    @Test func poolSumsBestSoloPerPartnerPerLevel() {
        let pool = MoonshotRewards.starPool([
            solo("one", levelA, 2), solo("one", levelA, 3),   // best 3 counts once
            solo("two", levelA, 1),                            // her card adds too
            solo("one", levelB, 2),
        ])
        #expect(pool == 3 + 1 + 2)
    }

    @Test func coopBestPoolsPerLevelAndAssistNever() {
        let pool = MoonshotRewards.starPool([
            .init(partnerID: "one", levelID: levelA, mode: .coop, cleared: true, bestStars: 2),
            .init(partnerID: "two", levelID: levelA, mode: .coop, cleared: true, bestStars: 3),
            .init(partnerID: "two", levelID: levelB, mode: .assist, cleared: true, bestStars: 3),
        ])
        #expect(pool == 3)   // coop max for levelA; assist banks nothing even if stars sneak in
    }

    @Test func grantsAccumulateAtThresholds() {
        #expect(MoonshotRewards.grants(pool: 7).isEmpty)
        #expect(MoonshotRewards.grants(pool: 8) == [.trail(.stardust)])
        #expect(MoonshotRewards.grants(pool: 24) == [.trail(.stardust), .trail(.petals), .character(.nox)])
    }

    @Test func noxGatesOnPoolOthersNever() {
        #expect(!MoonshotRewards.isUnlocked(.nox, pool: 23))
        #expect(MoonshotRewards.isUnlocked(.nox, pool: 24))
        #expect(MoonshotRewards.isUnlocked(.mochi, pool: 0))
    }

    @Test func nextMilestoneWalksTheTrackAndEnds() {
        #expect(MoonshotRewards.nextMilestone(pool: 0)?.threshold == 8)
        #expect(MoonshotRewards.nextMilestone(pool: 8)?.threshold == 16)
        #expect(MoonshotRewards.nextMilestone(pool: 95)?.threshold == 96)
        #expect(MoonshotRewards.nextMilestone(pool: 140) == nil)
    }

    @Test func previousThresholdFloorsTheProgressBar() {
        #expect(MoonshotRewards.previousThreshold(pool: 0) == 0)
        #expect(MoonshotRewards.previousThreshold(pool: 8) == 8)
        #expect(MoonshotRewards.previousThreshold(pool: 30) == 24)
    }

    @Test func extendedTrackAppendsWithoutRepricing() {
        #expect(MoonshotRewards.track.prefix(4).map(\.threshold) == [8, 16, 24, 32])  // M6: never reprice
        #expect(MoonshotRewards.grants(pool: 96).contains(.character(.misty)))
        #expect(MoonshotRewards.grants(pool: 96).contains(.theme(.dawn)))
        #expect(MoonshotRewards.grants(pool: 96).contains(.skin(.golden)))
        #expect(!MoonshotRewards.isUnlocked(.misty, pool: 59))
        #expect(MoonshotRewards.isUnlocked(.misty, pool: 60))
        #expect(MoonshotRewards.isUnlocked(.nox, pool: 24))          // unchanged by the append
    }

    @Test func deepTrackAppendsWithoutRepricing() {
        #expect(MoonshotRewards.track.map(\.threshold) == [8, 16, 24, 32, 45, 60, 78, 96, 110, 125, 140])
        #expect(MoonshotRewards.grants(pool: 140).contains(.trail(.comet)))
        #expect(MoonshotRewards.grants(pool: 140).contains(.theme(.midnight)))
        #expect(MoonshotRewards.grants(pool: 140).contains(.skin(.obsidian)))
        #expect(MoonshotRewards.nextMilestone(pool: 96)?.threshold == 110)
    }
}
