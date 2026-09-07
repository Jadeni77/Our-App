import Foundation
import CoreGraphics
import ImageIO

/// PNG → `HeightField`. The **only** image decoding in the package, kept in one
/// file so the rest of the world layer stays pure Swift and trivially testable.
public enum HeightFieldLoader {
    public enum LoadError: Error, Equatable {
        case assetMissing(String)
        case undecodable(String)
    }

    /// - Parameter bundle: `.module` in the app; injectable so tests can point
    ///   at a fixture without the package having an opinion about who hosts it.
    public static func load(_ definition: IslandDefinition, from bundle: Bundle) throws -> HeightField {
        guard let url = bundle.url(forResource: definition.assetName, withExtension: "png") else {
            throw LoadError.assetMissing(definition.assetName)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw LoadError.undecodable(definition.assetName)
        }

        let width = image.width, depth = image.height
        var samples = [UInt8](repeating: 0, count: width * depth)
        // Redraw into a known 8-bit gray buffer rather than trusting whatever
        // the file happened to be. A PNG can be palettised, 16-bit, or carry an
        // alpha channel, and reading its bytes directly would decode three
        // different ways depending on which editor last saved it.
        //
        // Done inside `withUnsafeMutableBytes` rather than
        // `CGContext(data: &samples, ...)`: the array-to-pointer conversion
        // `&samples` sugars is only guaranteed valid for the single call it
        // appears in, but the context keeps writing through that pointer for
        // as long as it lives — including the `.draw` call below. Keeping
        // both the context's creation and its use inside one closure keeps
        // every access inside the span Swift actually promises is valid.
        try samples.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress,
                                          width: width, height: depth,
                                          bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
                throw LoadError.undecodable(definition.assetName)
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: depth))
        }
        return HeightField(width: width, depth: depth, samples: samples)
    }
}
