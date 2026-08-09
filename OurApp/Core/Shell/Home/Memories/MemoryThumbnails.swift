import Observation
import SwiftUI

/// An in-memory cache of grid thumbnails, so scrolling doesn't re-read and
/// re-decode files on every render — the `ArtworkStore` pattern the springboard
/// already uses for external app icons.
@MainActor
@Observable
final class MemoryThumbnails {
    private var images: [String: UIImage] = [:]
    private let store: MemoryPhotoStore

    init(store: MemoryPhotoStore = MemoryPhotoStore()) {
        self.store = store
    }

    func image(for id: String) -> UIImage? { images[id] }

    /// Fails soft: a photo whose file has gone renders as a placeholder rather
    /// than crashing or retrying forever (principle 7).
    func loadIfNeeded(_ id: String) {
        guard images[id] == nil, let thumbnail = store.thumbnail(for: id) else { return }
        images[id] = thumbnail
    }
}
