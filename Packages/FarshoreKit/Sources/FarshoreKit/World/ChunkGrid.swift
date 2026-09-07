import Foundation

/// One rebuildable piece of terrain geometry.
public struct ChunkIndex: Hashable, Sendable {
    public let x: Int
    public let z: Int
    public init(x: Int, z: Int) { self.x = x; self.z = z }
}

/// How cells map onto rebuildable pieces.
public enum ChunkGrid {
    /// 32×32 cells ≈ 2,048 triangles per chunk. Small enough that rebuilding
    /// one is imperceptible, large enough that a 512 m island is 256 chunks
    /// rather than thousands of draw calls. The spike measured this.
    public static let cellsPerChunk = 32

    public static func chunk(containing cell: CellIndex) -> ChunkIndex {
        ChunkIndex(x: Int(floor(Double(cell.x) / Double(cellsPerChunk))),
                   z: Int(floor(Double(cell.z) / Double(cellsPerChunk))))
    }

    /// Every chunk whose geometry changes when this cell's height changes.
    ///
    /// **It is not always one.** Adjacent chunks share the vertices along their
    /// seam, so a cell sitting on a boundary is a vertex in up to four meshes.
    /// Rebuilding only "its" chunk leaves a visible tear along the seam — and
    /// no test of an interior edit would ever catch it, because interior edits
    /// really do touch exactly one.
    public static func chunksTouched(byEditing cell: CellIndex, in terrain: Terrain) -> Set<ChunkIndex> {
        var touched: Set<ChunkIndex> = []
        let onXSeam = cell.x % cellsPerChunk == 0
        let onZSeam = cell.z % cellsPerChunk == 0

        for dx in (onXSeam ? [-1, 0] : [0]) {
            for dz in (onZSeam ? [-1, 0] : [0]) {
                let candidate = ChunkIndex(x: chunk(containing: cell).x + dx,
                                           z: chunk(containing: cell).z + dz)
                guard candidate.x >= 0, candidate.z >= 0,
                      candidate.x < terrain.chunkCountX,
                      candidate.z < terrain.chunkCountZ else { continue }
                touched.insert(candidate)
            }
        }
        return touched
    }
}
