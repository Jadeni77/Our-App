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
        case .misty: 15
        case .pogo: 16
        }
    }

    /// SpriteKit body density — mochi is the heavy hitter, zip the dart.
    var density: CGFloat {
        switch self {
        case .mochi: 1.4
        case .zip: 1.0
        case .twinkle: 1.0
        case .nox: 1.2
        case .misty: 0.9   // she's made of mist
        case .pogo: 1.0    // springy, not heavy — the ricochet is his weight
        }
    }

    /// String Catalog key for the user-facing name (Mochi 团团 · Zip 嗖嗖 ·
    /// Twinkle 双双 · Nox 洞洞 · Pogo 蹦蹦).
    var displayNameKey: String {
        switch self {
        case .mochi: "Mochi"
        case .zip: "Zip"
        case .twinkle: "Twinkle"
        case .nox: "Nox"
        case .misty: "Misty"
        case .pogo: "Pogo"
        }
    }
}
