import Observation
import SwiftUI

/// An in-memory cache of grid thumbnails, so scrolling doesn't re-read and
/// re-decode files on every render — the `ArtworkStore` pattern the springboard
/// already uses for external app icons, including the two parts that matter:
/// the read happens **off** the main actor, and a **miss is cached** so a photo
/// whose file has gone isn't re-hit from disk on every cell appearance.
@MainActor
@Observable
final class MemoryThumbnails {
    /// One cache for the app. The grid and the sync tick have to be talking
    /// about the same one, or forgetting a miss on arrival has no effect on
    /// what the grid is showing.
    static let shared = MemoryThumbnails()

    /// `.some(nil)` means "looked, not there" — distinct from "not looked yet".
    private var images: [String: UIImage?] = [:]
    private let store: MemoryPhotoStore

    init(store: MemoryPhotoStore = MemoryPhotoStore()) {
        self.store = store
    }

    /// Drops a remembered **miss** so the next look hits the disk again.
    ///
    /// Miss-caching and asset sync are in direct tension: the cache exists so a
    /// lost file isn't re-read on every cell appearance, but a photo arriving
    /// from the other phone turns exactly that "lost" file into a present one.
    /// Without this, a synced memory would show a placeholder until the app was
    /// relaunched — which would look precisely like sync having failed.
    func forget(_ id: String) {
        images.removeValue(forKey: id)
    }

    func image(for id: String) -> UIImage? { images[id] ?? nil }

    func loadIfNeeded(_ id: String) async {
        guard images[id] == nil else { return }
        let store = self.store
        let loaded = await Task.detached(priority: .utility) {
            store.thumbnail(for: id)
        }.value
        // Re-checked after the await: two cells can ask at once.
        guard images[id] == nil else { return }
        images[id] = loaded
    }
}
