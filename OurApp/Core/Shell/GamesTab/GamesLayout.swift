import Foundation

/// The Games springboard layout: one ordered root grid whose items are loose
/// app tiles or folder-style collections. A per-device preference document
/// (P11) — not SwiftData records. Rules S5/S6 in docs/modules/games-springboard.md.
struct GamesLayout: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var items: [Item]

    /// Uniform identity for anything that occupies a grid slot.
    enum ItemID: Hashable {
        case app(String)        // module id
        case collection(UUID)
    }

    enum Item: Codable, Equatable, Identifiable {
        case app(moduleID: String)
        case collection(Collection)

        var id: ItemID {
            switch self {
            case .app(let moduleID): .app(moduleID)
            case .collection(let collection): .collection(collection.id)
            }
        }
    }

    struct Collection: Codable, Equatable, Identifiable {
        var id: UUID
        /// User data — stored verbatim, never translated (S6).
        var name: String
        /// Ordered module ids.
        var members: [String]
    }

    static func `default`(moduleIDs: [String]) -> GamesLayout {
        GamesLayout(version: currentVersion,
                    items: moduleIDs.map { .app(moduleID: $0) })
    }

    /// S5: never let layout drift block launching. Walk items in order keeping
    /// the first occurrence of each registered app id, drop stale ids, dissolve
    /// collections that end up empty, then append registered ids seen nowhere.
    func reconciled(with registeredIDs: [String]) -> GamesLayout {
        let registered = Set(registeredIDs)
        var seen = Set<String>()
        var result: [Item] = []

        for item in items {
            switch item {
            case .app(let moduleID):
                if registered.contains(moduleID), seen.insert(moduleID).inserted {
                    result.append(item)
                }
            case .collection(var collection):
                collection.members = collection.members.filter {
                    registered.contains($0) && seen.insert($0).inserted
                }
                if !collection.members.isEmpty {
                    result.append(.collection(collection))
                }
            }
        }
        for id in registeredIDs where !seen.contains(id) {
            result.append(.app(moduleID: id))
        }
        return GamesLayout(version: version, items: result)
    }
}
