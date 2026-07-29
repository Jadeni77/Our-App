import SwiftUI

/// What a module hands the shell so the launcher can show and mount it
/// (module contract, DESIGN.md §4). Nothing else crosses the seam.
struct ModuleDescriptor: Identifiable {
    let id: String
    /// Localized via the String Catalog — the launcher renders it directly.
    let name: LocalizedStringResource
    let emoji: String
    /// Type-erased so the shell never knows concrete module view types.
    let makeEntryView: @MainActor () -> AnyView
}
