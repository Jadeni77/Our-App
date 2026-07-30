import Foundation

/// The Games springboard layout: one ordered root grid whose items are loose
/// app tiles, folder-style collections, or external app tiles (S7). A
/// per-device preference document (P11) — not SwiftData records. Rules
/// S5/S6/S7 in docs/modules/games-springboard.md.
struct GamesLayout: Codable, Equatable {
    static let currentVersion = 2

    var version: Int
    var items: [Item]
    /// The registry external items and collection members reference (S7).
    /// Source of truth for external tiles — user data, never auto-dropped.
    var externalApps: [ExternalApp]
    /// Schemes proven on this phone (probe, Test launch, or a self-healed
    /// tap) — knowledge, not tiles: it outlives deletions and, once sync
    /// lands, travels to the other phone.
    var learnedSchemes: [LearnedScheme]

    init(version: Int, items: [Item], externalApps: [ExternalApp] = [],
         learnedSchemes: [LearnedScheme] = []) {
        self.version = version
        self.items = items
        self.externalApps = externalApps
        self.learnedSchemes = learnedSchemes
    }

    private enum CodingKeys: String, CodingKey {
        case version, items, externalApps, learnedSchemes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        items = try container.decode([Item].self, forKey: .items)
        // Older documents predate these keys — absent means none, and the
        // rest of the document decodes losslessly (S7 migration pattern).
        externalApps = try container.decodeIfPresent([ExternalApp].self,
                                                     forKey: .externalApps) ?? []
        learnedSchemes = try container.decodeIfPresent([LearnedScheme].self,
                                                       forKey: .learnedSchemes) ?? []
    }

    /// A runtime-verified launch scheme, named the way the owners see the
    /// game (S6 — the name is user data).
    struct LearnedScheme: Codable, Equatable {
        var name: String
        var scheme: String
    }

    /// Uniform identity for anything that occupies a grid slot.
    enum ItemID: Hashable {
        case app(String)        // module id
        case collection(UUID)
        case external(UUID)
    }

    enum Item: Codable, Equatable, Identifiable {
        case app(moduleID: String)
        case collection(Collection)
        case external(externalID: UUID)

        var id: ItemID {
            switch self {
            case .app(let moduleID): .app(moduleID)
            case .collection(let collection): .collection(collection.id)
            case .external(let externalID): .external(externalID)
            }
        }
    }

    struct Collection: Codable, Equatable, Identifiable {
        var id: UUID
        /// User data — stored verbatim, never translated (S6).
        var name: String
        /// Ordered member keys: module ids, or external UUID strings —
        /// `[String]` so version-1 documents decode losslessly.
        var members: [String]
    }

    /// A real app installed on the phone, launched from our springboard (S7).
    struct ExternalApp: Codable, Equatable, Identifiable {
        var id: UUID
        /// User data — stored verbatim, never translated (S6).
        var name: String
        /// Fallback glyph when no artwork is available.
        var emoji: String
        /// Official icon via the iTunes Search API, cached; emoji when absent.
        var artworkURL: URL?
        /// The app's custom URL scheme, e.g. identityv://
        var launchURL: URL?
        /// App Store page fallback.
        var storeURL: URL?
        /// The owner chose "Open App Store" at the link offer: skip the
        /// guessing entirely and go straight to the store (re-offered
        /// occasionally; cleared when a link is verified).
        var prefersStore: Bool

        init(id: UUID, name: String, emoji: String,
             artworkURL: URL?, launchURL: URL?, storeURL: URL?,
             prefersStore: Bool = false) {
            self.id = id
            self.name = name
            self.emoji = emoji
            self.artworkURL = artworkURL
            self.launchURL = launchURL
            self.storeURL = storeURL
            self.prefersStore = prefersStore
        }

        private enum CodingKeys: String, CodingKey {
            case id, name, emoji, artworkURL, launchURL, storeURL, prefersStore
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            emoji = try container.decode(String.self, forKey: .emoji)
            artworkURL = try container.decodeIfPresent(URL.self, forKey: .artworkURL)
            launchURL = try container.decodeIfPresent(URL.self, forKey: .launchURL)
            storeURL = try container.decodeIfPresent(URL.self, forKey: .storeURL)
            // Absent on tiles written before the preference existed.
            prefersStore = try container.decodeIfPresent(Bool.self,
                                                         forKey: .prefersStore) ?? false
        }

        /// How collections reference externals: `Collection.members` stays
        /// `[String]`, so externals slot in as their UUID string.
        var memberKey: String { id.uuidString }
    }

    func externalApp(withKey key: String) -> ExternalApp? {
        guard let uuid = UUID(uuidString: key) else { return nil }
        return externalApps.first { $0.id == uuid }
    }

    static func `default`(moduleIDs: [String]) -> GamesLayout {
        GamesLayout(version: currentVersion,
                    items: moduleIDs.map { .app(moduleID: $0) })
    }

    /// S5: never let layout drift block launching. Walk items in order keeping
    /// the first occurrence of each valid member key (registered module id or
    /// registry-backed external), drop stale references, dissolve collections
    /// that end up empty, then append registered modules seen nowhere — and
    /// re-materialize registry externals that lost their tile (S7: user data
    /// is never auto-dropped).
    func reconciled(with registeredIDs: [String]) -> GamesLayout {
        let registered = Set(registeredIDs)
        let externalKeys = Set(externalApps.map(\.memberKey))
        var seen = Set<String>()
        var result: [Item] = []

        for item in items {
            switch item {
            case .app(let moduleID):
                if registered.contains(moduleID), seen.insert(moduleID).inserted {
                    result.append(item)
                }
            case .external(let externalID):
                let key = externalID.uuidString
                if externalKeys.contains(key), seen.insert(key).inserted {
                    result.append(item)
                }
            case .collection(var collection):
                collection.members = collection.members.filter {
                    (registered.contains($0) || externalKeys.contains($0))
                        && seen.insert($0).inserted
                }
                if !collection.members.isEmpty {
                    result.append(.collection(collection))
                }
            }
        }
        for id in registeredIDs where seen.insert(id).inserted {
            result.append(.app(moduleID: id))
        }
        for app in externalApps where seen.insert(app.memberKey).inserted {
            result.append(.external(externalID: app.id))
        }
        return GamesLayout(version: version, items: result,
                           externalApps: externalApps,
                           learnedSchemes: learnedSchemes)
    }
}
