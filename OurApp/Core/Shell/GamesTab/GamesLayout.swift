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
}
