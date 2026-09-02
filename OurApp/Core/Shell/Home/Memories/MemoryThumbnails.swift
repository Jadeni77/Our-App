import Observation
import SwiftUI

/// An in-memory cache of grid thumbnails, so scrolling doesn't re-read and
/// re-decode files on every render — the `ArtworkStore` pattern the springboard
/// already uses for external app icons, including the two parts that matter:
/// the read happens **off** the main actor, and a **miss is cached** so a photo
/// whose file has gone isn't re-hit from disk on every cell appearance.
///
/// Also carries a second tier for the one full-size image outside a grid: the
/// album hero. `MemoryPhotoStore.thumbnailMaxPixel`'s own comment calls its
/// 400px copy the *grid* thumbnail on purpose — the hero is full-width by
/// 220pt, several times a grid tile's footprint on screen, and reading the
/// 400px copy there just upscales a small JPEG rather than showing the 2048px
/// one that already exists on disk. Same object, same off-main-actor read,
/// same miss-caching; a second dictionary because a cover already decoded at
/// 400px for the albums grid still needs its own, separate 2048px decode.
@MainActor
@Observable
final class MemoryThumbnails {
    /// One cache for the app. The grid and the sync tick have to be talking
    /// about the same one, or forgetting a miss on arrival has no effect on
    /// what the grid is showing.
    static let shared = MemoryThumbnails()

    /// `.some(nil)` means "looked, not there" — distinct from "not looked yet".
    private var images: [String: UIImage?] = [:]
    /// The hero's own tier, same shape as `images` — kept apart because a hit
    /// in one says nothing about the other: they're decodes of two different
    /// files at two different sizes.
    private var fullImages: [String: UIImage?] = [:]
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
    /// relaunched — which would look precisely like sync having failed. Clears
    /// both tiers: sync doesn't know or care which one happened to be asked
    /// for first, and a cover that was a miss in one is a miss in the other.
    func forget(_ id: String) {
        images.removeValue(forKey: id)
        fullImages.removeValue(forKey: id)
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

    /// The hero's read: the full 2048px copy, not the grid's 400px thumbnail.
    func fullImage(for id: String) -> UIImage? { fullImages[id] ?? nil }

    /// Same shape as `loadIfNeeded`, off the main actor, miss-cached the same
    /// way — the only difference is which of `MemoryPhotoStore`'s two files it
    /// reads.
    func loadFullIfNeeded(_ id: String) async {
        guard fullImages[id] == nil else { return }
        let store = self.store
        let loaded = await Task.detached(priority: .utility) {
            store.image(for: id)
        }.value
        guard fullImages[id] == nil else { return }
        fullImages[id] = loaded
    }
}
