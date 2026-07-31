import Foundation
import Testing
@testable import OurApp

struct MoonshotLevelTests {
    private static let v1JSON = """
    {"schemaVersion":1,"id":"AA000000-0000-4000-8000-000000000001","kind":"campaign",
     "createdAt":"2026-07-30T00:00:00Z","updatedAt":"2026-07-30T00:00:00Z","par":2,
     "queue":["mochi"],"buildZone":{"x":500,"y":0,"width":320,"height":340},
     "pieces":[],"glooms":[{"x":600,"y":16}]}
    """.data(using: .utf8)!

    @Test func v1FilesDecodeWithoutWorldOrWind() throws {
        let level = try MoonshotLevel.decoder().decode(MoonshotLevel.self, from: Self.v1JSON)
        #expect(level.worldNumber == 1)
        #expect(level.wind == nil)
    }

    @Test func windAndWorldRoundTrip() throws {
        var level = try MoonshotLevel.decoder().decode(MoonshotLevel.self, from: Self.v1JSON)
        level.world = 3
        level.wind = [WindZone(x: 300, y: 100, width: 200, height: 150, forceX: 3.0, forceY: 0)]
        let data = try MoonshotLevel.encoder().encode(level)
        let decoded = try MoonshotLevel.decoder().decode(MoonshotLevel.self, from: data)
        #expect(decoded.worldNumber == 3)
        #expect(decoded.wind == level.wind)
    }

    private func makeLevel(kind: LevelKind = .campaign,
                           pieces: [MoonshotLevel.Piece] = [],
                           glooms: [MoonshotLevel.GloomPlacement] = [.init(x: 600, y: 16)],
                           queue: [CharacterID] = [.mochi]) -> MoonshotLevel {
        MoonshotLevel(schemaVersion: 1, id: UUID(), kind: kind, authorID: nil,
                      createdAt: .now, updatedAt: .now, deletedAt: nil, title: nil,
                      par: 1, queue: queue,
                      buildZone: .init(x: 500, y: 0, width: 320, height: 340),
                      pieces: pieces, glooms: glooms)
    }

    @Test func codableRoundTripsExactly() throws {
        let level = makeLevel(pieces: [.init(shape: .plank, material: .moonwood, x: 600, y: 99, rotation: 0)])
        let data = try MoonshotLevel.encoder().encode(level)
        let decoded = try MoonshotLevel.decoder().decode(MoonshotLevel.self, from: data)
        // ISO-8601 truncates dates to the second, so whole-value equality
        // can't hold — compare the identity-bearing fields instead.
        #expect(decoded.id == level.id)
        #expect(decoded.pieces == level.pieces)
        #expect(decoded.queue == level.queue)
        #expect(decoded.kind == .campaign)
    }

    @Test func pieceCostIsSizeUnitsTimesMaterial() {
        #expect(MoonshotLevel.Piece(shape: .square, material: .crystal, x: 0, y: 0, rotation: 0).cost == 1)
        #expect(MoonshotLevel.Piece(shape: .plank, material: .moonwood, x: 0, y: 0, rotation: 0).cost == 4)
        #expect(MoonshotLevel.Piece(shape: .block, material: .meteorstone, x: 0, y: 0, rotation: 0).cost == 16)
        #expect(MoonshotLevel.Piece(shape: .square, material: .cloudfoam, x: 0, y: 0, rotation: 0).cost == 3)
    }

    @Test func totalCostSumsPieces() {
        let level = makeLevel(pieces: [
            .init(shape: .square, material: .crystal, x: 600, y: 22, rotation: 0),
            .init(shape: .column, material: .meteorstone, x: 650, y: 44, rotation: 0),
        ])
        #expect(level.totalCost == 1 + 8)
    }

    @Test func validBaseHasNoInvalidity() {
        let level = makeLevel(kind: .base,
            pieces: [.init(shape: .square, material: .crystal, x: 600, y: 22, rotation: 0)],
            glooms: [.init(x: 550, y: 16), .init(x: 600, y: 16), .init(x: 650, y: 16)])
        #expect(level.baseInvalidity(budget: MoonshotTuning.baseBudget) == nil)
    }

    @Test func baseInvalidityCatchesEachRule() {
        let frame = makeLevel(kind: .base,
            pieces: [.init(shape: .square, material: .frame, x: 600, y: 22, rotation: 0)],
            glooms: [.init(x: 550, y: 16), .init(x: 600, y: 16), .init(x: 650, y: 16)])
        #expect(frame.baseInvalidity(budget: 60) == .framePieces)

        let two = makeLevel(kind: .base, glooms: [.init(x: 550, y: 16), .init(x: 600, y: 16)])
        #expect(two.baseInvalidity(budget: 60) == .gloomCount(2))

        let out = makeLevel(kind: .base,
            pieces: [.init(shape: .square, material: .crystal, x: 100, y: 22, rotation: 0)],
            glooms: [.init(x: 550, y: 16), .init(x: 600, y: 16), .init(x: 650, y: 16)])
        #expect(out.baseInvalidity(budget: 60) == .outsideZone)

        let dear = makeLevel(kind: .base,
            pieces: (0..<5).map { .init(shape: .block, material: .meteorstone, x: 550 + Double($0) * 10, y: 44, rotation: 0) },
            glooms: [.init(x: 550, y: 16), .init(x: 600, y: 16), .init(x: 650, y: 16)])
        #expect(dear.baseInvalidity(budget: 60) == .overBudget(cost: 80))
    }
}
