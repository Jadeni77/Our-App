import Foundation
import Testing
@testable import FarshoreKit

/// Where food and water are, derived rather than stored — the same trick the
/// terrain uses (F2). Every device computes the same island, so it computes
/// the same berry bushes, and nothing has to travel.
struct ForageFieldTests {
    private func island() throws -> Terrain {
        Terrain(field: try HeightFieldLoader.load(.farshore01, from: .module),
                definition: .farshore01)
    }

    /// **The property everything else rests on.** If this ever stops being
    /// true, two phones sharing an island would disagree about where the food
    /// is — and nothing in the sync layer would ever tell them.
    @Test func thePointsAreTheSameEveryTime() throws {
        let terrain = try island()
        let first = ForageField.points(in: terrain, berries: 40, springs: 6)
        let second = ForageField.points(in: terrain, berries: 40, springs: 6)
        #expect(first == second)
    }

    @Test func itProducesTheRequestedCounts() throws {
        let points = ForageField.points(in: try island(), berries: 40, springs: 6)
        #expect(points.filter { $0.kind == .berries }.count == 40)
        #expect(points.filter { $0.kind == .spring }.count == 6)
    }

    @Test func idsAreUnique() throws {
        let points = ForageField.points(in: try island(), berries: 40, springs: 6)
        #expect(Set(points.map(\.id)).count == points.count)
    }

    /// Nothing edible grows in the sea. This is the test that catches a
    /// placement loop that forgot to reject water, which otherwise shows up as
    /// a berry bush the player can see and can never reach.
    @Test func nothingIsPlacedBelowSeaLevel() throws {
        let terrain = try island()
        for point in ForageField.points(in: terrain, berries: 40, springs: 6) {
            #expect(terrain.height(atX: point.x, z: point.z) > terrain.definition.seaLevel)
        }
    }

    @Test func everythingIsInsideTheIsland() throws {
        let terrain = try island()
        // `terrain.extent`, not a bound recomputed here. The version of
        // this test that wrote `width` (rather than `width - 1`) was a full
        // cell looser than the placer it was checking, so it pinned nothing
        // about which convention was in force.
        let extent = terrain.extent
        for point in ForageField.points(in: terrain, berries: 40, springs: 6) {
            #expect(point.x >= 0 && point.x <= extent)
            #expect(point.z >= 0 && point.z <= extent)
        }
    }

    /// **The same bound, on ground with no sea to hide behind.**
    ///
    /// `everythingIsInsideTheIsland` runs on the real heightmap, where the
    /// outer ring is water — so `height > seaLevel` rejects every candidate
    /// near the edge long before the extent bound is consulted, and I could
    /// not construct a change to the placer's extent that made that test
    /// fail. It is subsumed by `nothingIsPlacedBelowSeaLevel`, which is a
    /// polite way of saying it was not testing what its name claims.
    ///
    /// Flat ground entirely above water removes the guard that was doing
    /// the work, and leaves the extent as the only thing keeping points on
    /// the map.
    @Test func placementRespectsTheExtentWithNoSeaToStopIt() {
        let n = 65
        let terrain = Terrain(field: HeightField(width: n, depth: n,
                                                 samples: [UInt8](repeating: 128, count: n * n)),
                              definition: IslandDefinition(assetName: "flat", cellSize: 1,
                                                           heightScale: 100, seaLevel: 0))
        let points = ForageField.points(in: terrain,
                                        berries: ForageField.berriesPerIsland,
                                        springs: ForageField.springsPerIsland)
        #expect(points.count == ForageField.berriesPerIsland + ForageField.springsPerIsland)
        for point in points {
            #expect(point.x >= 0 && point.x <= terrain.extent)
            #expect(point.z >= 0 && point.z <= terrain.extent)
        }
    }

    @Test func berriesFeedYouAndSpringsWaterYou() {
        #expect(ForagePoint(id: 0, x: 0, z: 0, kind: .berries).need == .food)
        #expect(ForagePoint(id: 1, x: 0, z: 0, kind: .spring).need == .water)
    }

    /// `ActionButton` (Task 6) labels itself from this. Pinned as its own
    /// test rather than folded into `berriesFeedYouAndSpringsWaterYou`
    /// above: `need` and `action` are two separate switches over `kind`,
    /// and a future edit could get one right and the other wrong.
    @Test func berriesAreEatenAndSpringsAreDrunk() {
        #expect(ForagePoint(id: 0, x: 0, z: 0, kind: .berries).action == .eat)
        #expect(ForagePoint(id: 1, x: 0, z: 0, kind: .spring).action == .drink)
    }

    @Test func somethingNeverPickedIsAvailable() {
        #expect(ForageField.isAvailable(.berries, pickedAt: nil, now: Date()))
    }

    @Test func aJustPickedBushIsNotAvailable() {
        let now = Date()
        #expect(ForageField.isAvailable(.berries, pickedAt: now, now: now) == false)
    }

    @Test func aBushRegrowsAfterItsTime() {
        let picked = Date()
        let later = picked.addingTimeInterval(ForageField.regrowthSeconds + 1)
        #expect(ForageField.isAvailable(.berries, pickedAt: picked, now: later))
    }

    /// A spring is not consumed — water keeps coming out of it. Only forage
    /// has to regrow, and conflating the two would make thirst unsurvivable
    /// the moment you drank twice.
    @Test func aSpringIsAlwaysAvailable() {
        let now = Date()
        #expect(ForageField.isAvailable(.spring, pickedAt: now, now: now))
    }
}
