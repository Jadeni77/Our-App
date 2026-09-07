import Foundation
import Testing
@testable import FarshoreKit

/// "Rebuild only the changed chunk" is the performance claim the whole design
/// rests on, so what a single edit touches is a tested fact, not an assumption.
struct ChunkGridTests {
    private func terrain(width: Int = 96, depth: Int = 96) -> Terrain {
        Terrain(field: HeightField(width: width, depth: depth,
                                   samples: [UInt8](repeating: 0, count: width * depth)),
                definition: IslandDefinition(assetName: "test", cellSize: 1,
                                             heightScale: 10, seaLevel: 0))
    }

    @Test func aCellMapsIntoItsChunk() {
        #expect(ChunkGrid.chunk(containing: CellIndex(x: 0, z: 0)) == ChunkIndex(x: 0, z: 0))
        #expect(ChunkGrid.chunk(containing: CellIndex(x: 31, z: 31)) == ChunkIndex(x: 0, z: 0))
        #expect(ChunkGrid.chunk(containing: CellIndex(x: 32, z: 31)) == ChunkIndex(x: 1, z: 0))
    }

    /// An edit in the middle of a chunk is the cheap, common case.
    @Test func anInteriorEditTouchesOneChunk() {
        let touched = ChunkGrid.chunksTouched(byEditing: CellIndex(x: 10, z: 10), in: terrain())
        #expect(touched == [ChunkIndex(x: 0, z: 0)])
    }

    /// **The case that would silently crack the world open.** Chunks share the
    /// vertices along their seam, so editing a cell on the boundary changes
    /// geometry in the neighbour too. Rebuilding only "its" chunk leaves a
    /// visible tear that no test of the interior case would ever catch.
    @Test func anEditOnASeamTouchesBothSides() {
        let touched = ChunkGrid.chunksTouched(byEditing: CellIndex(x: 32, z: 10), in: terrain())
        #expect(touched == [ChunkIndex(x: 0, z: 0), ChunkIndex(x: 1, z: 0)])
    }

    @Test func anEditOnACornerTouchesFour() {
        let touched = ChunkGrid.chunksTouched(byEditing: CellIndex(x: 32, z: 32), in: terrain())
        #expect(touched == [ChunkIndex(x: 0, z: 0), ChunkIndex(x: 1, z: 0),
                            ChunkIndex(x: 0, z: 1), ChunkIndex(x: 1, z: 1)])
    }

    /// The spike's gate says at most four. Nothing may quietly exceed it.
    @Test func nothingEverTouchesMoreThanFour() {
        let world = terrain()
        for x in 0..<96 {
            for z in 0..<96 {
                let touched = ChunkGrid.chunksTouched(byEditing: CellIndex(x: x, z: z), in: world)
                #expect(touched.count <= 4)
            }
        }
    }

    /// **The guard this pins is invisible unless the edit is on a seam.**
    ///
    /// The upper-bound half is easy to test wrong: cell (95, 95) is not on a
    /// chunk boundary (95 % 32 = 31), so `chunksTouched` never enters the
    /// neighbour loop for it and the bounds guard never executes. Asserted
    /// alone, it passes with the whole guard deleted — verified by deleting
    /// it. Cell (0, 0) *is* on both seams, so the neighbour loop proposes
    /// chunks (−1, −1), (−1, 0) and (0, −1), and only the guard rejects them.
    ///
    /// It has to be an equality, not `allSatisfy`: the point is that the three
    /// negative candidates are *absent*, and a predicate over the surviving
    /// set cannot see something that is missing.
    ///
    /// This matters for slice 3, not slice 1. A leaked `ChunkIndex(x: -1, …)`
    /// reaching `TerrainNode.rebuild` hits a `guard let node = chunkNodes[index]
    /// else { return }` and is dropped in silence — so the visible symptom
    /// would be a torn seam along x = 0 after an edit, with no crash, no log
    /// and nothing anywhere that noticed.
    @Test func edgeChunksDoNotClaimNeighboursThatDoNotExist() {
        let world = terrain()
        let farCorner = ChunkGrid.chunksTouched(byEditing: CellIndex(x: 95, z: 95), in: world)
        #expect(farCorner.allSatisfy { $0.x < world.chunkCountX && $0.z < world.chunkCountZ })

        let origin = ChunkGrid.chunksTouched(byEditing: CellIndex(x: 0, z: 0), in: world)
        #expect(origin == [ChunkIndex(x: 0, z: 0)])
    }
}
