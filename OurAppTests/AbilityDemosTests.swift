import Foundation
import Testing
@testable import OurApp

struct AbilityDemosTests {
    @Test func everyDemoStageIsValidAndCastsItsCharacter() {
        for character in CharacterID.allCases {
            let demo = AbilityDemos.demo(for: character)
            #expect(demo.level.queue.first == character)
            #expect(demo.level.queue.count >= 2)          // the loop refills
            #expect(!demo.level.glooms.isEmpty)
            #expect(demo.level.pieces.allSatisfy { $0.x > 310 })
            #expect(demo.abilityDelay > 0)
            #expect(demo.pull.dx < 0)                     // pulls back, flies right
        }
    }

    @Test func demoStagesRoundTripTheLevelCodec() throws {
        for character in CharacterID.allCases {
            let demo = AbilityDemos.demo(for: character)
            let data = try MoonshotLevel.encoder().encode(demo.level)
            let decoded = try MoonshotLevel.decoder().decode(MoonshotLevel.self, from: data)
            #expect(decoded.pieces == demo.level.pieces)
            #expect(decoded.queue == demo.level.queue)
        }
    }

    @Test func demoStacksKeepTheirAirGaps() {
        // The stability rule from World 2 applies to demo stages too:
        // stacked dynamic columns sit 1pt apart (45 → 134), planks 2pt
        // above column tops (102 over an 89 top), glooms 1pt over perches.
        for character in CharacterID.allCases {
            let level = AbilityDemos.demo(for: character).level
            for piece in level.pieces where piece.shape == .column {
                #expect(piece.y == 45 || piece.y == 134)
            }
            for piece in level.pieces where piece.shape == .plank {
                #expect(piece.y == 102)
            }
            for gloom in level.glooms {
                #expect(gloom.y == 16 || gloom.y == 106)
            }
        }
    }
}
