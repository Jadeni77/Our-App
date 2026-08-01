import Foundation
import Testing
@testable import OurApp

struct CoachLedgerTests {
    private func level(world: Int = 1, queue: [CharacterID] = [.mochi]) -> MoonshotLevel {
        MoonshotLevel(schemaVersion: 1, id: UUID(), kind: .campaign, authorID: nil,
                      createdAt: .now, updatedAt: .now, deletedAt: nil, title: nil,
                      par: 1, queue: queue,
                      buildZone: .init(x: 500, y: 0, width: 320, height: 340),
                      pieces: [], glooms: [.init(x: 600, y: 16)],
                      world: world == 1 ? nil : world)
    }

    @Test func firstEverOpenTeachesGoalAndDrag() {
        let moments = CoachLedger.momentsAtLevelOpen(level: level(), seen: [])
        #expect(moments == [.goal, .dragToFling])
    }

    @Test func mochiNeverGetsACard() {
        // Drag + goal introduce him; a "meet mochi" card would be noise.
        let moments = CoachLedger.momentsAtLevelOpen(level: level(queue: [.mochi, .mochi]),
                                                     seen: ["goal", "drag"])
        #expect(moments.isEmpty)
    }

    @Test func unmetQueueMembersGetCardsInQueueOrder() {
        let moments = CoachLedger.momentsAtLevelOpen(
            level: level(queue: [.zip, .twinkle, .zip]),
            seen: ["goal", "drag", "meet-twinkle"])
        #expect(moments == [.meetCharacter(.zip)])
    }

    @Test func worldMechanicFiresOncePerWorldAndNeverForWorldOne() {
        #expect(CoachLedger.momentsAtLevelOpen(level: level(world: 2), seen: ["goal", "drag"])
                == [.worldMechanic(2)])
        #expect(CoachLedger.momentsAtLevelOpen(level: level(world: 2),
                                               seen: ["goal", "drag", "world-2"]).isEmpty)
        #expect(CoachLedger.momentsAtLevelOpen(level: level(world: 1), seen: ["goal", "drag"]).isEmpty)
    }

    @Test func openOrderIsGoalDragWorldThenCards() {
        let moments = CoachLedger.momentsAtLevelOpen(level: level(world: 3, queue: [.nox, .mochi]),
                                                     seen: [])
        #expect(moments == [.goal, .dragToFling, .worldMechanic(3), .meetCharacter(.nox)])
    }

    @Test func swapAvailableCharactersGetCardsAfterQueueOnes() {
        let moments = CoachLedger.momentsAtLevelOpen(
            level: level(queue: [.zip]), swapCharacters: [.nox, .misty],
            seen: ["goal", "drag", "meet-nox"])
        #expect(moments == [.meetCharacter(.zip), .meetCharacter(.misty)])
    }

    @Test func unmetGloomKindsGetBannersAfterCards() {
        var lvl = level(queue: [.zip])
        lvl.glooms = [.init(x: 600, y: 16, kind: .shield),
                      .init(x: 650, y: 16, kind: .shield),
                      .init(x: 700, y: 16, kind: .mist)]
        let moments = CoachLedger.momentsAtLevelOpen(
            level: lvl, swapCharacters: [],
            seen: ["goal", "drag", "meet-zip", "gloom-mist"])
        #expect(moments == [.meetGloom(.shield)])
    }

    @Test func classicGloomsNeedNoIntroduction() {
        let moments = CoachLedger.momentsAtLevelOpen(level: level(), seen: ["goal", "drag"])
        #expect(moments.isEmpty)
    }

    @Test func abilityCueFiresOnceEver() {
        #expect(CoachLedger.momentInFlight(seen: []) == .abilityTap)
        #expect(CoachLedger.momentInFlight(seen: ["ability"]) == nil)
    }

    @Test func storageKeysRoundTripTheCast() {
        #expect(CoachMoment.meetCharacter(.misty).storageKey == "meet-misty")
        #expect(CoachMoment.worldMechanic(2).storageKey == "world-2")
    }
}
