import Foundation

/// Which way this module wants the device held. **Our own enum on purpose.**
/// The shell has one called `ModuleOrientation`, and importing it would be
/// exactly the dependency P39 forbids — the host maps between them.
public enum FarshoreOrientation: Sendable {
    case portrait, landscape
}

/// Everything a host needs to show and mount this game. Nothing else crosses.
public enum FarshoreModuleInfo {
    public static let id = "farshore"
    public static let emoji = "🏝️"
    /// Landscape for the same reason Moonshot is (M13): a 3D world wants the
    /// width. Revisitable from the device — it is an open question in the
    /// module doc, not a settled one.
    public static let orientation = FarshoreOrientation.landscape

    /// Resolved from **this package's** catalog, never the app's.
    public static var title: LocalizedStringResource {
        LocalizedStringResource("farshore.title",
                                defaultValue: "Farshore",
                                bundle: .atURL(Bundle.module.bundleURL))
    }
}
