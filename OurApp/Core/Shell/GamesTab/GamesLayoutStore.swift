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
        layout = Self.load(from: fileURL, moduleIDs: ids).reconciled(with: ids)
        save()
    }

    func module(for id: String) -> ModuleDescriptor? { modulesByID[id] }

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
            // file silently becomes the default layout.
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
              let targetIndex = layout.items.firstIndex(where: { $0.id == .app(target) }),
              layout.items.contains(where: { $0.id == .app(dragged) })
        else { return nil }
        let collection = GamesLayout.Collection(id: UUID(), name: name,
                                                members: [target, dragged])
        layout.items[targetIndex] = .collection(collection)
        layout.items.removeAll { $0.id == .app(dragged) }
        save()
        return collection.id
    }

    func addToCollection(_ collectionID: UUID, moduleID: String) {
        guard layout.items.contains(where: { $0.id == .app(moduleID) }),
              let index = collectionIndex(collectionID),
              case .collection(var collection) = layout.items[index]
        else { return }
        collection.members.append(moduleID)
        layout.items[index] = .collection(collection)
        layout.items.removeAll { $0.id == .app(moduleID) }
        save()
    }

    func moveMember(in collectionID: UUID, moduleID: String, toIndex: Int) {
        guard let index = collectionIndex(collectionID),
              case .collection(var collection) = layout.items[index],
              let from = collection.members.firstIndex(of: moduleID)
        else { return }
        let member = collection.members.remove(at: from)
        collection.members.insert(member, at: min(max(toIndex, 0), collection.members.count))
        layout.items[index] = .collection(collection)
        save()
    }

    func moveMemberToRoot(_ moduleID: String, from collectionID: UUID) {
        guard let index = collectionIndex(collectionID),
              case .collection(var collection) = layout.items[index],
              let from = collection.members.firstIndex(of: moduleID)
        else { return }
        collection.members.remove(at: from)
        if collection.members.isEmpty {
            layout.items.remove(at: index)          // auto-dissolve (S5)
        } else {
            layout.items[index] = .collection(collection)
        }
        layout.items.append(.app(moduleID: moduleID))
        save()
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
