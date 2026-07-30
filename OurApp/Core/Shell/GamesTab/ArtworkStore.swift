import Observation
import UIKit

/// Disk + memory cache for external app artwork (S7): one PNG per external
/// id under Application Support. `image(for:)` is a pure memory read (safe
/// in `body`); `loadIfNeeded` does the one disk read per id off the main
/// actor and caches misses so they aren't retried every render. Everything
/// fails soft to nil — the tile falls back to its emoji (principle 7).
@MainActor
@Observable
final class ArtworkStore {
    private let directory: URL
    /// `.some(nil)` is a cached miss — looked on disk, nothing there.
    private var images: [UUID: UIImage?] = [:]

    init(directory: URL = ArtworkStore.defaultDirectory()) {
        self.directory = directory
    }

    nonisolated static func defaultDirectory() -> URL {
        URL.applicationSupportDirectory.appendingPathComponent("ExternalArtwork",
                                                               isDirectory: true)
    }

    /// Pure memory read — never touches disk, never mutates state.
    func image(for id: UUID) -> UIImage? {
        images[id] ?? nil
    }

    /// One disk read per id per launch; hit or miss, the answer is cached.
    func loadIfNeeded(_ id: UUID) async {
        guard images.index(forKey: id) == nil else { return }
        let url = fileURL(for: id)
        let loaded = await Task.detached(priority: .utility) {
            (try? Data(contentsOf: url)).flatMap(UIImage.init(data:))
        }.value
        // A store/forget that landed while we were reading wins.
        guard images.index(forKey: id) == nil else { return }
        images[id] = .some(loaded)
    }

    func storeArtwork(_ data: Data, for id: UUID) {
        guard let image = UIImage(data: data) else { return }
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: id), options: .atomic)
        images[id] = .some(image)
    }

    /// Downloads and replaces whatever is cached — the enrich path calls this
    /// when the artwork URL changed (first fetch, or a rename found a
    /// different app). Failures leave the previous state in place.
    func refreshArtwork(from url: URL, for id: UUID) async {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        storeArtwork(data, for: id)
    }

    /// Downloads only when nothing is cached yet — the tile's self-heal path
    /// for a persisted `artworkURL` whose download once failed. Concurrent
    /// callers may both download; the writes are idempotent.
    func fetchArtwork(from url: URL, for id: UUID) async {
        await loadIfNeeded(id)
        guard image(for: id) == nil else { return }
        await refreshArtwork(from: url, for: id)
    }

    /// Deleting an external forgets its artwork on disk — the in-memory
    /// image deliberately survives so the tile's removal animation keeps its
    /// face instead of flashing the 🎮 fallback; memory clears next launch.
    func forget(_ id: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: id))
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).png")
    }
}
