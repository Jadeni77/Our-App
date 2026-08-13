import SwiftUI

/// The drawn icons a special date can wear — twelve, chosen to cover what a
/// couple actually records. Replaces the emoji palette: emoji are Apple's art
/// where principle 9 wants ours.
enum DateIcon: String, CaseIterable {
    case cake, plane, home, ring, heart, gift
    case camera, star, wave, graduation, flower, pin

    /// Light → deep, hand-tuned inside the app's pastel range.
    ///
    /// Twelve hues cannot come from `Theme`'s five stops, and deriving them
    /// mechanically produced muddy colour when we tried it for the hub icons
    /// (H10). The cost of hand-tuning, stated plainly: if the palette is ever
    /// re-tuned, these must be re-tuned with it and nothing will catch it.
    var accent: (light: Color, deep: Color) {
        switch self {
        case .cake:       (Color(red: 0.97, green: 0.72, blue: 0.80), Color(red: 0.87, green: 0.47, blue: 0.62))
        case .plane:      (Color(red: 0.72, green: 0.85, blue: 0.95), Color(red: 0.42, green: 0.62, blue: 0.85))
        case .home:       (Color(red: 1.00, green: 0.85, blue: 0.72), Color(red: 0.90, green: 0.60, blue: 0.45))
        case .ring:       (Color(red: 0.80, green: 0.75, blue: 0.95), Color(red: 0.55, green: 0.50, blue: 0.80))
        case .heart:      (Color(red: 0.98, green: 0.70, blue: 0.78), Color(red: 0.85, green: 0.40, blue: 0.55))
        case .gift:       (Color(red: 0.99, green: 0.78, blue: 0.72), Color(red: 0.90, green: 0.50, blue: 0.45))
        case .camera:     (Color(red: 0.75, green: 0.80, blue: 0.92), Color(red: 0.48, green: 0.55, blue: 0.78))
        case .star:       (Color(red: 1.00, green: 0.88, blue: 0.68), Color(red: 0.92, green: 0.68, blue: 0.35))
        case .wave:       (Color(red: 0.72, green: 0.90, blue: 0.88), Color(red: 0.35, green: 0.68, blue: 0.68))
        case .graduation: (Color(red: 0.76, green: 0.78, blue: 0.92), Color(red: 0.45, green: 0.46, blue: 0.75))
        case .flower:     (Color(red: 0.93, green: 0.78, blue: 0.93), Color(red: 0.75, green: 0.48, blue: 0.78))
        case .pin:        (Color(red: 0.78, green: 0.92, blue: 0.82), Color(red: 0.45, green: 0.72, blue: 0.55))
        }
    }

    /// What VoiceOver calls it. Without this every button in the picker
    /// announces the same word and the grid is unusable without sight.
    ///
    /// `house` rather than `home`: the catalog's "Home" is the tab label, which
    /// translates to 首页 — the wrong word entirely for a building.
    var name: LocalizedStringResource {
        switch self {
        case .cake:       "Cake"
        case .plane:      "Plane"
        case .home:       "House"
        case .ring:       "Ring"
        case .heart:      "Heart"
        case .gift:       "Gift"
        case .camera:     "Camera"
        case .star:       "Star"
        case .wave:       "Wave"
        case .graduation: "Graduation"
        case .flower:     "Flower"
        case .pin:        "Place"
        }
    }

    /// A stored id → an icon. Unknown ids (a future version's, or the `""` a
    /// row carries before migration) resolve to `.heart` rather than failing,
    /// which is why `iconID` is stored as a raw string (the `cuisineID`
    /// precedent, F6).
    static func resolve(_ id: String) -> DateIcon {
        DateIcon(rawValue: id) ?? .heart
    }

    /// The retired emoji palette → an icon. Used once, by the V1→V2 migration
    /// that drops `SpecialDate.emoji`; nothing writes emoji any more.
    /// `camera` appears nowhere here: it is a new option the palette never had.
    static func matching(emoji: String) -> DateIcon {
        switch emoji {
        case "🎂", "🍰": .cake
        case "✈️":       .plane
        case "🏠":       .home
        case "💍":       .ring
        case "🎓":       .graduation
        case "🌸":       .flower
        case "🎁":       .gift
        case "⭐️":       .star
        case "💗":       .heart
        case "🌊":       .wave
        case "📍":       .pin
        default:         .heart
        }
    }
}
