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

    /// **Which way the ground faces was, until the final branch review,
    /// untested — and inverting every normal left all 41 tests green.**
    ///
    /// That is not a cosmetic gap. An inward-facing surface under
    /// physically-based lighting is lit from behind: it renders black, or near
    /// enough. This branch has already been bitten twice by exactly that
    /// symptom (the raw `.hdr` as lighting environment, and the daylight sky
    /// left up through the night), and both times it cost device time to find
    /// something a value assertion would have caught in milliseconds.
    ///
    /// Flat ground makes the expected answer exact rather than approximate:
    /// with every height equal, the central differences are zero and the
    /// normal is `(0, 2·cellSize, 0)` normalised — straight up, no tolerance
    /// argument to have.
    @Test func aFlatChunkFacesStraightUp() {
        let geometry = TerrainMeshBuilder.geometry(for: ChunkIndex(x: 0, z: 0), in: flatTerrain())
        let normals = Self.vectors(from: geometry.sources(for: .normal).first)
        #expect(normals.count == 33 * 33)
        #expect(normals.allSatisfy { abs($0.x) < 0.0001 && abs($0.z) < 0.0001 })
        // `> 0.9999`, not `abs(y) > 0.9999`: an inverted normal is exactly
        // what this exists to catch, and a magnitude test would pass for it.
        #expect(normals.allSatisfy { $0.y > 0.9999 })
    }

    /// The other half of "renders black": **winding**.
    ///
    /// Normals feed the shading, but the rasteriser decides visibility from
    /// vertex order — front faces are counter-clockwise seen from the front.
    /// Swap two indices per triangle and the normals still say "up" while the
    /// island turns inside out: it disappears when you stand on it and is
    /// visible only from below. Nothing pinned this either, so both failure
    /// modes in the same family were open at once.
    ///
    /// Checked geometrically rather than by comparing index order, so it stays
    /// true if the builder is ever rewritten to emit triangles differently.
    @Test func everyTriangleWindsFrontFaceUp() {
        let geometry = TerrainMeshBuilder.geometry(for: ChunkIndex(x: 0, z: 0), in: flatTerrain())
        let vertices = Self.vectors(from: geometry.sources(for: .vertex).first)
        let indices = Self.indices(from: geometry.elements.first)
        #expect(indices.count == 32 * 32 * 6)

        var upwardFaces = 0
        for triangle in stride(from: 0, to: indices.count, by: 3) {
            let a = vertices[indices[triangle]]
            let b = vertices[indices[triangle + 1]]
            let c = vertices[indices[triangle + 2]]
            let ab = SCNVector3(b.x - a.x, b.y - a.y, b.z - a.z)
            let ac = SCNVector3(c.x - a.x, c.y - a.y, c.z - a.z)
            // Only the y component of ab × ac matters on flat ground: positive
            // means counter-clockwise seen from above, i.e. facing the sky.
            let crossY = ab.z * ac.x - ab.x * ac.z
            if crossY > 0 { upwardFaces += 1 }
        }
        #expect(upwardFaces == indices.count / 3)
    }

    // MARK: - Reading geometry back

    /// `SCNGeometrySource` has no accessor for its values, so unpack the raw
    /// buffer. Asserting the layout first rather than assuming it: if SceneKit
    /// ever hands back `Double` components or an interleaved stride, a wrong
    /// reader would produce garbage that reads as a *terrain* bug.
    private static func vectors(from source: SCNGeometrySource?) -> [SCNVector3] {
        guard let source else { return [] }
        #expect(source.bytesPerComponent == MemoryLayout<Float>.size)
        #expect(source.componentsPerVector == 3)
        return source.data.withUnsafeBytes { raw in
            (0..<source.vectorCount).map { index in
                let base = source.dataOffset + index * source.dataStride
                return SCNVector3(
                    raw.loadUnaligned(fromByteOffset: base, as: Float.self),
                    raw.loadUnaligned(fromByteOffset: base + 4, as: Float.self),
                    raw.loadUnaligned(fromByteOffset: base + 8, as: Float.self)
                )
            }
        }
    }

    private static func indices(from element: SCNGeometryElement?) -> [Int] {
        guard let element else { return [] }
        #expect(element.primitiveType == .triangles)
        #expect(element.bytesPerIndex == MemoryLayout<Int32>.size)
        let count = element.primitiveCount * 3
        return element.data.withUnsafeBytes { raw in
            (0..<count).map { Int(raw.loadUnaligned(fromByteOffset: $0 * 4, as: Int32.self)) }
        }
    }
}
