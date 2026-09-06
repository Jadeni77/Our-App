import Foundation
import Testing
@testable import FarshoreKit

/// The asset IS the terrain (F2), so "did it load, and is it the shape we
/// think" is a real test rather than a formality.
struct HeightFieldLoaderTests {
    @Test func itLoadsTheShippedIsland() throws {
        let field = try HeightFieldLoader.load(.farshore01, from: .module)
        #expect(field.width == 512)
        #expect(field.depth == 512)
        #expect(field.samples.count == 512 * 512)
    }

    /// It has to actually be an island: high in the middle, at sea level all
    /// the way round. A loader that silently returned zeroes would pass every
    /// other test in this file.
    @Test func theIslandIsHighInTheMiddleAndLowAtTheEdges() throws {
        let field = try HeightFieldLoader.load(.farshore01, from: .module)
        #expect(field.sample(x: 256, z: 256) > 100)
        #expect(field.sample(x: 0, z: 0) == 0)
        #expect(field.sample(x: 511, z: 511) == 0)
    }

    @Test func aMissingAssetFailsSoftlyAndSaysWhich() {
        let missing = IslandDefinition(assetName: "no-such-island",
                                       cellSize: 1, heightScale: 1, seaLevel: 0)
        #expect(throws: HeightFieldLoader.LoadError.self) {
            try HeightFieldLoader.load(missing, from: .module)
        }
    }
}
