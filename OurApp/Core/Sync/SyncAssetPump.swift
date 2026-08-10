import Foundation
import SwiftData

/// Moves photo bytes in both directions, separately from records.
///
/// Records outrun their pictures on purpose: a memory's note and date are worth
/// having immediately, and a placeholder that fills in a moment later is a much
/// better experience than a timeline that waits on megabytes.
///
/// Retry is structural rather than a mechanism: anything still missing is
/// simply attempted again on the next tick, because "what is missing" is
/// recomputed from the store each time rather than remembered in a queue that
/// could itself get lost.
@MainActor
enum SyncAssetPump {
    /// Ids confirmed to be in the cloud, so a tick doesn't re-upload everything.
    private static let uploadedKey = "sync.uploadedAssets"

    static func upload(context: ModelContext,
                       transport: any SyncAssetTransport,
                       photos: MemoryPhotoStore = MemoryPhotoStore(),
                       defaults: UserDefaults = .standard) async {
        guard let memories = try? context.fetch(FetchDescriptor<Memory>()) else { return }
        var confirmed = Set(defaults.stringArray(forKey: uploadedKey) ?? [])

        for memory in memories {
            for id in memory.photoIDs where !confirmed.contains(id) {
                // Only what this phone actually holds. A photo we are still
                // waiting to receive is not ours to upload.
                guard let data = photos.storedData(for: id) else { continue }
                do {
                    try await transport.putAsset(data, id: id)
                    confirmed.insert(id)
                } catch {
                    // Left unconfirmed on purpose — the next tick retries it.
                    continue
                }
            }
        }
        defaults.set(Array(confirmed), forKey: uploadedKey)
    }

    /// - Returns: the ids that landed, so a view can drop its cached misses.
    @discardableResult
    static func download(context: ModelContext,
                         transport: any SyncAssetTransport,
                         photos: MemoryPhotoStore) async -> [String] {
        guard let memories = try? context.fetch(
            FetchDescriptor<Memory>(predicate: Memory.visible)) else { return [] }

        var arrived: [String] = []
        for memory in memories {
            for id in memory.photoIDs where !photos.has(id) {
                // `try?` flattens the throw and the "not uploaded yet" nil into
                // one skip, which is right: both mean "try again next tick".
                guard let bytes = try? await transport.getAsset(id: id) else { continue }
                // Resized off the main actor: this is ImageIO work on a
                // multi-megabyte file, and the tick runs while the grid is on
                // screen.
                let written = await Task.detached(priority: .utility) { () -> Bool in
                    (try? photos.write(bytes, id: id)) != nil
                }.value
                if written { arrived.append(id) }
            }
        }
        return arrived
    }
}
