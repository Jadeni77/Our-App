import Foundation
import Testing
@testable import OurApp

struct LevelSessionTests {
    private func makeSession(queue: [CharacterID] = [.mochi, .zip], glooms: Int = 1, par: Int = 1) -> LevelSession {
        LevelSession(level: MoonshotLevel(
            schemaVersion: 1, id: UUID(), kind: .campaign, authorID: nil,
            createdAt: .now, updatedAt: .now, deletedAt: nil, title: nil,
            par: par, queue: queue,
            buildZone: .init(x: 500, y: 0, width: 320, height: 340), pieces: [],
            glooms: (0..<glooms).map { .init(x: Double(550 + 50 * $0), y: 16) }))
    }

    @Test func happyPathToThreeStarWin() {
        let s = makeSession()
        #expect(s.phase == .ready)
        #expect(s.currentCharacter == .mochi)
        s.beginAim()
        #expect(s.phase == .aiming)
        s.fling()
        #expect(s.phase == .inFlight)
        #expect(s.flingsUsed == 1)
        s.gloomPopped()
        s.flightEnded()
        #expect(s.phase == .settling)
        s.settled()
        #expect(s.phase == .won(stars: 3))
    }

    @Test func abilityFiresOnceAndOnlyInFlight() {
        let s = makeSession()
        #expect(s.tapAbility() == nil)                 // ready: no
        s.beginAim()
        s.fling()
        #expect(s.tapAbility() == .mochi)              // first tap works
        #expect(s.tapAbility() == nil)                 // second tap doesn't
    }

    @Test func queueAdvancesAndAbilityResets() {
        let s = makeSession(glooms: 2)
        s.beginAim(); s.fling(); _ = s.tapAbility(); s.gloomPopped(); s.flightEnded(); s.settled()
        #expect(s.phase == .ready)
        #expect(s.currentCharacter == .zip)
        #expect(!s.abilityUsedThisFlight)
    }

    @Test func exhaustedQueueWithGloomsLeftFails() {
        let s = makeSession(queue: [.mochi], glooms: 1)
        s.beginAim(); s.fling(); s.flightEnded(); s.settled()
        #expect(s.phase == .failed)
    }

    @Test func winWaitsForSettleAndCountsSpareFlings() {
        let s = makeSession(queue: [.mochi, .zip, .twinkle], glooms: 1, par: 2)
        s.beginAim(); s.fling(); s.gloomPopped()
        #expect(s.phase == .inFlight)                  // popping doesn't win mid-air
        s.flightEnded(); s.settled()
        #expect(s.phase == .won(stars: 3))             // 1 fling ≤ par 2
    }

    @Test func cancelAimReturnsToReadyWithoutSpendingAFling() {
        let s = makeSession()
        s.beginAim(); s.cancelAim()
        #expect(s.phase == .ready)
        #expect(s.flingsUsed == 0)
    }
}
