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
}
