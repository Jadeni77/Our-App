import Foundation
import SceneKit

/// One chunk of terrain as `SCNGeometry`.
public enum TerrainMeshBuilder {
    /// Metres per texture repeat, for the ground's UVs below. Declared once,
    /// here, because the mesh's UV computation and the ground material's
    /// texture tiling have to agree exactly — two files each hardcoding their
    /// own `4.0` would drift the moment either changed without the other.
    /// `IslandLook` (the ground material) references this constant rather
    /// than redeclaring it.
    public static let textureScale: Double = 4.0

    /// Builds the chunk **inclusive of its far edge**: a 32-cell chunk is 33
    /// vertices across, and its last column is its neighbour's first. Sharing
    /// the seam is what keeps the island watertight; dropping it leaves a
    /// hairline crack visible only at chunk boundaries.
    public static func geometry(for chunk: ChunkIndex, in terrain: Terrain) -> SCNGeometry {
        let cells = ChunkGrid.cellsPerChunk
        let side = cells + 1
        let cellSize = Float(terrain.definition.cellSize)
        let originX = chunk.x * cells
        let originZ = chunk.z * cells

        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uvs: [CGPoint] = []
        vertices.reserveCapacity(side * side)

        for i in 0..<side {
            for j in 0..<side {
                let cellX = originX + j
                let cellZ = originZ + i
                let worldX = Double(cellX) * terrain.definition.cellSize
                let worldZ = Double(cellZ) * terrain.definition.cellSize
                let y = terrain.height(atX: worldX, z: worldZ)
                vertices.append(SCNVector3(Float(worldX), Float(y), Float(worldZ)))

                // Central differences over one cell. Cheaper and steadier than
                // averaging face normals, and it reads the same interpolated
                // surface the player actually walks on.
                let hx0 = terrain.height(atX: worldX - terrain.definition.cellSize, z: worldZ)
                let hx1 = terrain.height(atX: worldX + terrain.definition.cellSize, z: worldZ)
                let hz0 = terrain.height(atX: worldX, z: worldZ - terrain.definition.cellSize)
                let hz1 = terrain.height(atX: worldX, z: worldZ + terrain.definition.cellSize)
                var normal = SCNVector3(Float(hx0 - hx1), 2 * cellSize, Float(hz0 - hz1))
                let length = sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z)
                if length > 0 { normal = SCNVector3(normal.x / length, normal.y / length, normal.z / length) }
                normals.append(normal)

                // Tiled in world units so the material's scale is independent
                // of chunk size — change `cellsPerChunk` and the ground does
                // not suddenly look different.
                uvs.append(CGPoint(x: worldX / textureScale, y: worldZ / textureScale))
            }
        }

        var indices: [Int32] = []
        indices.reserveCapacity(cells * cells * 6)
        for i in 0..<cells {
            for j in 0..<cells {
                let topLeft = Int32(i * side + j)
                let topRight = topLeft + 1
                let bottomLeft = Int32((i + 1) * side + j)
                let bottomRight = bottomLeft + 1
                indices += [topLeft, bottomLeft, topRight,
                            topRight, bottomLeft, bottomRight]
            }
        }

        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices),
                      SCNGeometrySource(normals: normals),
                      SCNGeometrySource(textureCoordinates: uvs)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        geometry.name = "chunk-\(chunk.x)-\(chunk.z)"
        return geometry
    }
}
