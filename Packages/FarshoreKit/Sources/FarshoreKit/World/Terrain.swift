import Foundation

/// A cell of the heightmap grid — the unit an edit is addressed to. Slice 3's
/// `TerrainEdit` derives its id from `(worldID, x, z)`, so this is the type
/// that later makes two people digging one hole write one row.
public struct CellIndex: Hashable, Sendable {
    public let x: Int
    public let z: Int
    public init(x: Int, z: Int) { self.x = x; self.z = z }
}

/// The island in metres.
public struct Terrain: Sendable {
    public let field: HeightField
    public let definition: IslandDefinition

    public init(field: HeightField, definition: IslandDefinition) {
        self.field = field
        self.definition = definition
    }

    /// How far the island reaches, in metres, from the origin corner.
    ///
    /// **`width - 1`, not `width`, and it lives here so that only has to be
    /// got right once.** The heightmap is a grid of *vertices*, not of
    /// tiles: 512 samples describe 511 cells, so the last sample sits at
    /// `511 * cellSize`. Asking for anything beyond that samples off the
    /// end of the field.
    ///
    /// This is the "one decision, two literals" defect wearing its least
    /// visible costume — an *expression* rather than a number, which a grep
    /// for repeated literals slides straight past. Three places had already
    /// written it three different ways (the forage placer with the `- 1`,
    /// the coordinator's spawn point without it, a test's bound without it
    /// either), disagreeing by half a cell and agreeing with nothing. Slice
    /// 3's placements and slice 6's shared world would each have picked one
    /// of the three.
    public var extent: Double {
        Double(field.width - 1) * definition.cellSize
    }

    /// The middle of the island — where the player lands and where the
    /// campfire burns. Derived from `extent` so it cannot drift from it.
    public var centre: (x: Double, z: Double) {
        (x: extent / 2, z: extent / 2)
    }

    public var chunkCountX: Int {
        Int(ceil(Double(field.width - 1) / Double(ChunkGrid.cellsPerChunk)))
    }
    public var chunkCountZ: Int {
        Int(ceil(Double(field.depth - 1) / Double(ChunkGrid.cellsPerChunk)))
    }

    /// Ground height in metres, **bilinearly interpolated**.
    ///
    /// Interpolation is not polish. The asset is 8-bit, so raw samples step in
    /// `heightScale / 255` increments (~16 cm here); reading them directly
    /// would terrace every gentle slope on the island. Interpolating between
    /// them costs three lerps and removes the whole problem.
    public func height(atX x: Double, z: Double) -> Double {
        let gx = x / definition.cellSize
        let gz = z / definition.cellSize
        let x0 = Int(floor(gx)), z0 = Int(floor(gz))
        let fx = gx - Double(x0), fz = gz - Double(z0)

        let h00 = Double(field.sample(x: x0,     z: z0))
        let h10 = Double(field.sample(x: x0 + 1, z: z0))
        let h01 = Double(field.sample(x: x0,     z: z0 + 1))
        let h11 = Double(field.sample(x: x0 + 1, z: z0 + 1))

        let top = h00 + (h10 - h00) * fx
        let bottom = h01 + (h11 - h01) * fx
        let blended = top + (bottom - top) * fz

        return blended / 255.0 * definition.heightScale
    }

    public func cell(atX x: Double, z: Double) -> CellIndex {
        CellIndex(x: Int(floor(x / definition.cellSize)),
                  z: Int(floor(z / definition.cellSize)))
    }

    public func worldPosition(of cell: CellIndex) -> (x: Double, z: Double) {
        (x: Double(cell.x) * definition.cellSize,
         z: Double(cell.z) * definition.cellSize)
    }
}
