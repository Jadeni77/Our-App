import Foundation
import Testing
@testable import FarshoreKit

/// The heightmap is the one thing every device must agree on exactly — it is
/// what replaces "generate from a seed" (F2). Sampling has to be a pure
/// function of the asset, with no floating-point drift anybody could argue with.
struct TerrainTests {
    /// A 3×3 field: flat 0 except the middle sample at 255.
    private func spike() -> Terrain {
        var samples = [UInt8](repeating: 0, count: 9)
        samples[4] = 255
        let field = HeightField(width: 3, depth: 3, samples: samples)
        let definition = IslandDefinition(assetName: "test",
                                          cellSize: 1.0,
                                          heightScale: 100.0,
                                          seaLevel: 0)
        return Terrain(field: field, definition: definition)
    }

    @Test func aSampleReadsItsFullHeight() {
        #expect(spike().height(atX: 1.0, z: 1.0) == 100.0)
    }

    @Test func betweenSamplesItInterpolates() {
        // Halfway from the 0 at (0,1) to the 255 at (1,1).
        #expect(abs(spike().height(atX: 0.5, z: 1.0) - 50.0) < 0.0001)
    }

    /// Off the edge must clamp rather than trap. A player walking off the map
    /// is a bug, but crashing is a worse one, and the fail-soft principle says
    /// which way to lean (principle 7).
    @Test func outsideTheFieldItClampsToTheEdge() {
        #expect(spike().height(atX: -50.0, z: -50.0) == 0.0)
        #expect(spike().height(atX: 500.0, z: 500.0) == 0.0)
    }

    @Test func worldPositionAndCellRoundTrip() {
        let terrain = spike()
        let cell = terrain.cell(atX: 2.0, z: 1.0)
        #expect(cell == CellIndex(x: 2, z: 1))
        let back = terrain.worldPosition(of: cell)
        #expect(back.x == 2.0)
        #expect(back.z == 1.0)
    }

    @Test func cellSizeScalesWorldDistance() {
        var samples = [UInt8](repeating: 0, count: 9)
        samples[4] = 255
        let field = HeightField(width: 3, depth: 3, samples: samples)
        let definition = IslandDefinition(assetName: "test",
                                          cellSize: 4.0,
                                          heightScale: 100.0,
                                          seaLevel: 0)
        let terrain = Terrain(field: field, definition: definition)
        // The peak sample now sits 4 metres out, not 1.
        #expect(terrain.height(atX: 4.0, z: 4.0) == 100.0)
    }
}
