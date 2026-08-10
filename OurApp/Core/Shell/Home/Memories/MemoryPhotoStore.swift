import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Where a memory's pictures live. Bytes never go in the database — the record
/// keeps filenames, the same split `CoupleIdentityStore` uses for avatars, and
/// the one that makes these `CKAsset`s rather than blobs when sync lands.
struct MemoryPhotoStore {
    /// Long edge of the stored copy. 2048 is indistinguishable from the
    /// original on a phone and roughly a tenth of the bytes — which matters
    /// twice, once for local storage and once for what sync has to carry.
    static let fullMaxPixel = 2048
    /// Long edge of the grid thumbnail, so scrolling never decodes a full image.
    static let thumbnailMaxPixel = 400

    enum Failure: Error { case unreadable, encodingFailed }

    let directory: URL

    /// `directory` is injectable for tests; the default is Application Support,
    /// which unlike Documents isn't user-visible in the Files app.
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Memories", isDirectory: true)
    }

    func url(_ id: String) -> URL { directory.appendingPathComponent("\(id).jpg") }
    func thumbnailURL(_ id: String) -> URL { directory.appendingPathComponent("\(id)-thumb.jpg") }

    /// Writes a downscaled copy and a thumbnail; returns the new photo's id.
    func save(_ data: Data) throws -> String {
        let full = try downscaled(data, maxPixel: Self.fullMaxPixel)
        let thumbnail = try downscaled(data, maxPixel: Self.thumbnailMaxPixel)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID().uuidString
        try full.write(to: url(id), options: .atomic)
        do {
            try thumbnail.write(to: thumbnailURL(id), options: .atomic)
        } catch {
            // Otherwise the full-size file is an orphan: nothing references it,
            // and there is no sweeper anywhere that would ever find it.
            try? FileManager.default.removeItem(at: url(id))
            throw error
        }
        return id
    }

    func image(for id: String) -> UIImage? { UIImage(contentsOfFile: url(id).path) }
    func thumbnail(for id: String) -> UIImage? { UIImage(contentsOfFile: thumbnailURL(id).path) }

    func delete(_ id: String) {
        try? FileManager.default.removeItem(at: url(id))
        try? FileManager.default.removeItem(at: thumbnailURL(id))
    }

    /// ImageIO, deliberately, not `UIImage` + redraw.
    ///
    /// `CGImageSourceCreateThumbnailAtIndex` resizes straight from the encoded
    /// source without ever holding the full decoded bitmap; the `UIImage` path
    /// does, and importing several 12-megapixel photos at once is exactly where
    /// that spikes and gets the app jetsammed.
    func downscaled(_ data: Data, maxPixel: Int) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw Failure.unreadable
        }
        // Clamp to the source's own size. `…ThumbnailFromImageAlways` with a
        // max-pixel-size will happily *upscale* a smaller photo to that size —
        // more bytes and worse quality than the original, which is the opposite
        // of the point.
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let sourceLongEdge = max(properties?[kCGImagePropertyPixelWidth] as? Int ?? 0,
                                 properties?[kCGImagePropertyPixelHeight] as? Int ?? 0)
        let target = sourceLongEdge > 0 ? min(maxPixel, sourceLongEdge) : maxPixel

        let options: [CFString: Any] = [
            // Load-bearing: without it ImageIO can hand back a small embedded
            // EXIF preview instead of a real resize, and the symptom is
            // "photos are mysteriously blurry" rather than an error.
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Honours EXIF orientation, so a portrait photo doesn't come back
            // on its side with the tag stripped.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: target,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw Failure.unreadable
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
                output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw Failure.encodingFailed
        }
        CGImageDestinationAddImage(
            destination, image,
            [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encodingFailed }
        return output as Data
    }
}
