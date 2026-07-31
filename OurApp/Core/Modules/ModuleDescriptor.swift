import SwiftUI

/// Which way a mounted module wants the device held (contract extension,
/// Moonshot M13): the host rotates in on mount and restores portrait on exit.
enum ModuleOrientation {
    case portrait, landscape
}

/// What a module hands the shell so the launcher can show and mount it
/// (module contract, DESIGN.md §4). Nothing else crosses the seam.
struct ModuleDescriptor: Identifiable {
    let id: String
    /// Localized via the String Catalog — the launcher renders it directly.
    let name: LocalizedStringResource
    let emoji: String
    let orientation: ModuleOrientation
    /// Type-erased so the shell never knows concrete module view types.
    let makeEntryView: @MainActor () -> AnyView

    init(id: String,
         name: LocalizedStringResource,
         emoji: String,
         orientation: ModuleOrientation = .portrait,
         makeEntryView: @escaping @MainActor () -> AnyView) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.orientation = orientation
        self.makeEntryView = makeEntryView
    }
}
