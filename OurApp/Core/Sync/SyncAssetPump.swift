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
    static func upload(context: ModelContext,
                       transport: any SyncAssetTransport,
                       photos: MemoryPhotoStore = MemoryPhotoStore()) async {
        guard let memories = try? context.fetch(FetchDescriptor<Memory>()) else { return }

        for memory in memories {
            for id in memory.photoIDs {
                // Only what this phone actually holds. A photo we are still
                // waiting to receive is not ours to upload.
                guard let data = photos.storedData(for: id) else { continue }
                // **Asked, not remembered.** This used to consult a growing set
                // in `UserDefaults`, keyed globally rather than per cloud — so
                // pointing at a fresh folder, or losing an asset server-side,
                // meant those ids were never re-uploaded and the partner's grid
                // kept its placeholders forever. Derived state can't go stale.
                guard await !transport.hasAsset(id: id) else { continue }
                // A throw just means the next tick tries again.
                try? await transport.putAsset(data, id: id)
            }
        }
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
