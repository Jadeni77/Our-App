import SwiftUI
import FarshoreKit

/// **The whole boundary between OurApp and game #2** (P39).
///
/// `FarshoreKit` is a package, so it cannot import this target — every
/// forbidden dependency is a compile error rather than a review note. This file
/// is the translation layer, and extraction is deleting it: point a new app at
/// the same package and `FarshoreRootView` is unchanged.
///
/// Two more adapter files are coming and are deliberately NOT here yet:
/// `FarshoreSchema` in slice 3, `FarshoreSyncAdapter` in slice 6.
enum FarshoreModule {
    @MainActor static var descriptor: ModuleDescriptor {
        ModuleDescriptor(
            id: FarshoreModuleInfo.id,
            name: FarshoreModuleInfo.title,
            emoji: FarshoreModuleInfo.emoji,
            orientation: orientation(FarshoreModuleInfo.orientation),
            makeEntryView: { AnyView(FarshoreRootView()) }
        )
    }

    /// The package declares its own orientation enum on purpose — reaching for
    /// the shell's `ModuleOrientation` is exactly the dependency P39 forbids,
    /// so the mapping lives here, in the file extraction deletes.
    private static func orientation(_ preference: FarshoreOrientation) -> ModuleOrientation {
        switch preference {
        case .portrait: return .portrait
        case .landscape: return .landscape
        }
    }
}
