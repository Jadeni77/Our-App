import SwiftUI

/// Tile metadata for the shell's launcher (module contract). Game #1:
/// slingshot-physics destruction in the app's own moonlit world — see
/// docs/modules/moonshot.md for the full design.
enum MoonshotModule {
    @MainActor static var descriptor: ModuleDescriptor {
        ModuleDescriptor(
            id: "moonshot",
            name: "Moonshot",
            emoji: "🌙",
            orientation: .landscape,   // M13 — the whole module rotates, one coherent space
            makeEntryView: { AnyView(MoonshotHomeView()) }
        )
    }
}
