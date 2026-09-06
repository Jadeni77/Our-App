import Foundation
import SceneKit
import Testing
@testable import FarshoreKit

struct TerrainMeshBuilderTests {
    private func flatTerrain() -> Terrain {
        let n = 65   // exactly two chunks across, plus the shared seam column
        return Terrain(field: HeightField(width: n, depth: n,
                                          samples: [UInt8](repeating: 128, count: n * n)),
                       definition: IslandDefinition(assetName: "t", cellSize: 1,
                                                    heightScale: 100, seaLevel: 0))
    }

    @Test func aChunkHasAVertexPerCellCorner() {
        let geometry = TerrainMeshBuilder.geometry(for: ChunkIndex(x: 0, z: 0), in: flatTerrain())
        let vertices = geometry.sources(for: .vertex).first
        // 32 cells → 33 vertices per side.
        #expect(vertices?.vectorCount == 33 * 33)
    }

    @Test func aChunkHasTwoTrianglesPerCell() {
        let geometry = TerrainMeshBuilder.geometry(for: ChunkIndex(x: 0, z: 0), in: flatTerrain())
        #expect(geometry.elements.first?.primitiveCount == 32 * 32 * 2)
    }

    @Test func itCarriesNormalsAndTextureCoordinates() {
        let geometry = TerrainMeshBuilder.geometry(for: ChunkIndex(x: 0, z: 0), in: flatTerrain())
        #expect(geometry.sources(for: .normal).isEmpty == false)
        #expect(geometry.sources(for: .texcoord).isEmpty == false)
    }

    /// **The seam test.** Chunk 0's last vertex column and chunk 1's first must
    /// be the same point in space. If the builder starts chunk 1 one cell late,
    /// the island has a crack down it that only appears at chunk boundaries —
    /// exactly the kind of wrong that looks almost right.
    @Test func neighbouringChunksShareTheirSeam() {
        let terrain = flatTerrain()
        let left = TerrainMeshBuilder.geometry(for: ChunkIndex(x: 0, z: 0), in: terrain)
        let right = TerrainMeshBuilder.geometry(for: ChunkIndex(x: 1, z: 0), in: terrain)
        let leftBox = left.boundingBox
        let rightBox = right.boundingBox
        #expect(abs(leftBox.max.x - rightBox.min.x) < 0.0001)
    }

    @Test func aFlatFieldMeshesAtItsScaledHeight() {
        let geometry = TerrainMeshBuilder.geometry(for: ChunkIndex(x: 0, z: 0), in: flatTerrain())
        // 128/255 × 100 m ≈ 50.2 m
        #expect(abs(Double(geometry.boundingBox.min.y) - 50.196) < 0.01)
    }
}
