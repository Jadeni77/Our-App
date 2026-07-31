import Foundation

/// The cast's physical identities (M3). Names are placeholder localized data
/// — the owners christen them over gameplay; the String Catalog keys below
/// are what code touches, so renaming never means refactoring.
extension CharacterID {
    /// Body radius in points.
    var radius: CGFloat {
        switch self {
        case .mochi: 18
        case .zip: 14
        case .twinkle: 16
        case .nox: 15
        }
    }

    /// SpriteKit body density — mochi is the heavy hitter, zip the dart.
    var density: CGFloat {
        switch self {
        case .mochi: 1.4
        case .zip: 1.0
        case .twinkle: 1.0
        case .nox: 1.2
        }
    }

    /// String Catalog key for the user-facing name (Mochi 团团 · Zip 嗖嗖 ·
    /// Twinkle 双双 · Nox 洞洞).
    var displayNameKey: String {
        switch self {
        case .mochi: "Mochi"
        case .zip: "Zip"
        case .twinkle: "Twinkle"
        case .nox: "Nox"
        }
    }
}
