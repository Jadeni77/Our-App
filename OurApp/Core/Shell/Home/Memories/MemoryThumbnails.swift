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
    /// `.some(nil)` means "looked, not there" — distinct from "not looked yet".
    private var images: [String: UIImage?] = [:]
    private let store: MemoryPhotoStore

    init(store: MemoryPhotoStore = MemoryPhotoStore()) {
        self.store = store
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
