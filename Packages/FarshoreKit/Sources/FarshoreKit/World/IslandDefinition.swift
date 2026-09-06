import Foundation

/// Which authored island this is, and how its pixels become metres.
///
/// The island is **authored, not generated** (F2): at the fidelity this game
/// targets, art direction beats procedural variety. The asset is the source of
/// truth — it is a plain grayscale PNG anyone can open and edit — and the
/// property that mattered survives untouched: nothing about the terrain ever
/// travels between devices, because every device loads the same file.
public struct IslandDefinition: Sendable, Equatable {
    /// Base name of the heightmap in the package bundle, without extension.
    public let assetName: String
    /// Metres between adjacent heightmap samples.
    public let cellSize: Double
    /// Metres represented by a fully white sample (255).
    public let heightScale: Double
    /// Metres. Anything below this is under water.
    public let seaLevel: Double

    public init(assetName: String, cellSize: Double, heightScale: Double, seaLevel: Double) {
        self.assetName = assetName
        self.cellSize = cellSize
        self.heightScale = heightScale
        self.seaLevel = seaLevel
    }

    /// The one island slice 1 ships. 512 samples at 1 m = a ~512 m island,
    /// crossable in a couple of minutes at walking pace, which is the size the
    /// design asks for.
    public static let farshore01 = IslandDefinition(assetName: "farshore-01",
                                                    cellSize: 1.0,
                                                    heightScale: 42.0,
                                                    seaLevel: 3.0)
}
