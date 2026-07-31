import UIKit

/// Tasteful haptics (principle 9): soft taps for interactions, success on milestones.
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    /// A hard knock — destruction, collisions (Moonshot's pieces shattering).
    static func thud() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
