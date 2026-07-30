import Foundation
import Observation

/// Owns the springboard layout: loads/saves the per-device JSON preference
/// document and applies every mutation (P11). Views read `layout` and call
/// mutations; nothing else touches the file.
@MainActor
@Observable
final class GamesLayoutStore {
    private(set) var layout: GamesLayout
    /// Registration order — the shell hands this in; also the default layout order.
    let modules: [ModuleDescriptor]

    private let modulesByID: [String: ModuleDescriptor]
    private let fileURL: URL

    init(modules: [ModuleDescriptor], fileURL: URL = GamesLayoutStore.defaultFileURL()) {
        self.modules = modules
        self.modulesByID = Dictionary(uniqueKeysWithValues: modules.map { ($0.id, $0) })
        self.fileURL = fileURL
        let ids = modules.map(\.id)
        var loaded = Self.load(from: fileURL, moduleIDs: ids).reconciled(with: ids)
        // Saves always carry the running build's schema version — older
        // documents are migrated (losslessly) the moment they're loaded.
        loaded.version = GamesLayout.currentVersion
        layout = loaded
        save()
    }

    func module(for id: String) -> ModuleDescriptor? { modulesByID[id] }

    func externalApp(forKey key: String) -> GamesLayout.ExternalApp? {
        layout.externalApp(withKey: key)
    }

    func externalApp(id: UUID) -> GamesLayout.ExternalApp? {
        layout.externalApps.first { $0.id == id }
    }

    /// The glyph a collection's 3×3 mini-grid shows for a member key.
    func glyph(forMember member: String) -> String {
        module(for: member)?.emoji ?? externalApp(forKey: member)?.emoji ?? ""
    }

    // MARK: - Persistence

    nonisolated static func defaultFileURL() -> URL {
        let directory = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        return directory.appendingPathComponent("GamesLayout.json")
    }

    nonisolated private static func load(from url: URL, moduleIDs: [String]) -> GamesLayout {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(GamesLayout.self, from: data),
              decoded.version <= GamesLayout.currentVersion
        else {
            // Fail-soft (principle 7): a missing, corrupt, or from-the-future
            // file silently becomes the default layout — but the bytes carry
            // user-authored externals (S7), so preserve them for hand recovery
            // before the first save overwrites the file.
            if FileManager.default.fileExists(atPath: url.path) {
                let stamp = Int(Date().timeIntervalSince1970)
                let backup = url.deletingLastPathComponent()
                    .appendingPathComponent("\(url.lastPathComponent).unreadable-\(stamp)")
                try? FileManager.default.moveItem(at: url, to: backup)
            }
            return .default(moduleIDs: moduleIDs)
        }
        return decoded
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(layout) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Mutations (each persists immediately)

    func moveItem(id: GamesLayout.ItemID, toIndex: Int) {
        guard let from = layout.items.firstIndex(where: { $0.id == id }) else { return }
        let item = layout.items.remove(at: from)
        layout.items.insert(item, at: min(max(toIndex, 0), layout.items.count))
        save()
    }

    @discardableResult
    func formCollection(target: String, dragged: String, named name: String) -> UUID? {
        guard target != dragged,
              let targetID = rootTileID(forMember: target),
              let draggedID = rootTileID(forMember: dragged),
              let targetIndex = layout.items.firstIndex(where: { $0.id == targetID })
        else { return nil }
        let collection = GamesLayout.Collection(id: UUID(), name: name,
                                                members: [target, dragged])
        layout.items[targetIndex] = .collection(collection)
        layout.items.removeAll { $0.id == draggedID }
        save()
        return collection.id
    }

    func addToCollection(_ collectionID: UUID, member: String) {
        guard let memberID = rootTileID(forMember: member),
              let index = collectionIndex(collectionID),
              case .collection(var collection) = layout.items[index]
        else { return }
        collection.members.append(member)
        layout.items[index] = .collection(collection)
        layout.items.removeAll { $0.id == memberID }
        save()
    }

    func moveMember(in collectionID: UUID, member: String, toIndex: Int) {
        guard let index = collectionIndex(collectionID),
              case .collection(var collection) = layout.items[index],
              let from = collection.members.firstIndex(of: member)
        else { return }
        let moved = collection.members.remove(at: from)
        collection.members.insert(moved, at: min(max(toIndex, 0), collection.members.count))
        layout.items[index] = .collection(collection)
        save()
    }

    func moveMemberToRoot(_ member: String, from collectionID: UUID) {
        guard let index = collectionIndex(collectionID),
              case .collection(var collection) = layout.items[index],
              let from = collection.members.firstIndex(of: member)
        else { return }
        collection.members.remove(at: from)
        if collection.members.isEmpty {
            layout.items.remove(at: index)          // auto-dissolve (S5)
        } else {
            layout.items[index] = .collection(collection)
        }
        layout.items.append(item(forMember: member))
        save()
    }

    // MARK: - External apps (S7)

    func addExternalApp(_ app: GamesLayout.ExternalApp) {
        guard !layout.externalApps.contains(where: { $0.id == app.id }) else { return }
        layout.externalApps.append(app)
        layout.items.append(.external(externalID: app.id))
        save()
    }

    func updateExternalApp(_ app: GamesLayout.ExternalApp) {
        guard let index = layout.externalApps.firstIndex(where: { $0.id == app.id })
        else { return }
        layout.externalApps[index] = app
        save()
    }

    /// The one deletion the springboard allows (S7): externals are user-added,
    /// so the user removes them — modules never can be. Strips the registry
    /// entry, the root tile, and every collection reference (dissolving
    /// collections that empty, S5).
    func deleteExternalApp(id: UUID) {
        let key = id.uuidString
        layout.externalApps.removeAll { $0.id == id }
        layout.items = layout.items.compactMap { item in
            switch item {
            case .external(let externalID) where externalID == id:
                return nil
            case .collection(var collection):
                collection.members.removeAll { $0 == key }
                return collection.members.isEmpty ? nil : .collection(collection)
            default:
                return item
            }
        }
        save()
    }

    /// Resolves a member key to the root tile carrying it, if one exists.
    private func rootTileID(forMember member: String) -> GamesLayout.ItemID? {
        let candidate = item(forMember: member).id
        return layout.items.contains { $0.id == candidate } ? candidate : nil
    }

    /// The root item a member key materializes as: an external tile when the
    /// registry backs it, a module tile otherwise.
    private func item(forMember member: String) -> GamesLayout.Item {
        if let uuid = UUID(uuidString: member),
           layout.externalApps.contains(where: { $0.id == uuid }) {
            return .external(externalID: uuid)
        }
        return .app(moduleID: member)
    }

    func renameCollection(_ collectionID: UUID, to name: String) {
        guard let index = collectionIndex(collectionID),
              case .collection(var collection) = layout.items[index] else { return }
        collection.name = name
        layout.items[index] = .collection(collection)
        save()
    }

    private func collectionIndex(_ id: UUID) -> Int? {
        layout.items.firstIndex(where: { $0.id == .collection(id) })
    }
}
