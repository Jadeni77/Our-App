import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import FarshoreKit

/// Regression coverage for the loader's CoreGraphics round trip.
///
/// The shipped island (`farshore-01.png`) is radially symmetric — its falloff
/// is a function of `hypot(nx, ny)` alone — so
/// `theIslandIsHighInTheMiddleAndLowAtTheEdges` cannot tell a correct load
/// from one flipped horizontally, flipped vertically, or transposed: all
/// three land the samples that test reads back at exactly the same values.
/// This test builds an asymmetric fixture instead, one marker pixel whose
/// position differs under all three of those transforms, writes it through
/// the same CoreGraphics path the real generator uses, and loads it back
/// through the production loader. A future change that reintroduces a flip
/// or transpose fails here even though it would pass every other test in
/// this file.
struct HeightFieldLoaderOrientationTests {
    private struct FixtureWriteFailed: Error {}

    @Test func loadingPreservesRowAndColumnOrientation() throws {
        let width = 8, depth = 8
        let markerX = 2, markerZ = 5   // x != z, so flip/flip/transpose all disagree
        var pixels = [UInt8](repeating: 0, count: width * depth)
        pixels[markerZ * width + markerX] = 255

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HeightFieldLoaderOrientationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let assetName = "orientation-fixture"
        let fileURL = directory.appendingPathComponent("\(assetName).png")

        // The same write path `Tools/farshore-heightmap/make-heightmap.swift`
        // uses: raw buffer -> 8-bit gray CGContext -> CGImage -> PNG.
        let space = CGColorSpaceCreateDeviceGray()
        try pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: depth,
                                          bitsPerComponent: 8, bytesPerRow: width, space: space,
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue),
                  let image = context.makeImage(),
                  let destination = CGImageDestinationCreateWithURL(fileURL as CFURL,
                                                                    UTType.png.identifier as CFString, 1, nil)
            else {
                throw FixtureWriteFailed()
            }
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }

        // A plain temp directory works as a resource bundle: `Bundle(url:)`
        // treats its root as the search location for top-level resources,
        // exactly like the package's own `.module` bundle does for its PNG.
        let bundle = try #require(Bundle(url: directory))
        let definition = IslandDefinition(assetName: assetName, cellSize: 1, heightScale: 1, seaLevel: 0)
        let field = try HeightFieldLoader.load(definition, from: bundle)

        // The marker must land back at exactly (markerX, markerZ) — not at
        // its horizontal mirror, vertical mirror, or transpose. Any one of
        // those three going wrong flips a distinct pair of these assertions.
        #expect(field.sample(x: markerX, z: markerZ) == 255)
        #expect(field.sample(x: width - 1 - markerX, z: markerZ) == 0)   // would catch a horizontal flip
        #expect(field.sample(x: markerX, z: depth - 1 - markerZ) == 0)   // would catch a vertical flip
        #expect(field.sample(x: markerZ, z: markerX) == 0)               // would catch a transpose
    }
}
