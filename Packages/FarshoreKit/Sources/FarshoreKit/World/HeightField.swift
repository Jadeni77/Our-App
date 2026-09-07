import Foundation

/// The raw sample grid, exactly as it came off the PNG. Integer access only —
/// everything to do with metres lives in `Terrain`, so this stays a dumb,
/// trivially testable container.
public struct HeightField: Sendable, Equatable {
    public let width: Int
    public let depth: Int
    public let samples: [UInt8]

    public init(width: Int, depth: Int, samples: [UInt8]) {
        precondition(samples.count == width * depth, "sample count must be width × depth")
        self.width = width
        self.depth = depth
        self.samples = samples
    }

    /// **Clamped, never trapping.** Sampling runs from the mesher, from
    /// locomotion, and from anything that asks where the ground is; one
    /// off-by-one anywhere would otherwise be a crash rather than a seam.
    /// Fail soft (principle 7).
    public func sample(x: Int, z: Int) -> UInt8 {
        let cx = min(max(x, 0), width - 1)
        let cz = min(max(z, 0), depth - 1)
        return samples[cz * width + cx]
    }
}
