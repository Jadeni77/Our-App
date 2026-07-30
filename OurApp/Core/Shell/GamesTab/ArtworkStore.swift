import Observation
import UIKit

/// Disk + memory cache for external app artwork (S7): one PNG per external
/// id under Application Support. Everything fails soft to nil — the tile
/// falls back to its emoji (principle 7).
@MainActor
@Observable
final class ArtworkStore {
    private let directory: URL
    private var images: [UUID: UIImage] = [:]

    init(directory: URL = ArtworkStore.defaultDirectory()) {
        self.directory = directory
    }

    nonisolated static func defaultDirectory() -> URL {
        URL.applicationSupportDirectory.appendingPathComponent("ExternalArtwork",
                                                               isDirectory: true)
    }

    func image(for id: UUID) -> UIImage? {
        if let cached = images[id] { return cached }
        guard let data = try? Data(contentsOf: fileURL(for: id)),
              let image = UIImage(data: data) else { return nil }
        images[id] = image
        return image
    }

    func storeArtwork(_ data: Data, for id: UUID) {
        guard let image = UIImage(data: data) else { return }
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: id), options: .atomic)
        images[id] = image
    }

    /// Downloads once and caches; failures leave the emoji fallback in place.
    func fetchArtwork(from url: URL, for id: UUID) async {
        guard image(for: id) == nil,
              let (data, _) = try? await URLSession.shared.data(from: url)
        else { return }
        storeArtwork(data, for: id)
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).png")
    }
}
