import Foundation

/// Material physics + the impulse damage model (M7): a readable destruction
/// hierarchy — crystal shatters, moonwood cracks then splinters, meteorstone
/// shrugs off everything but slams and the gravity well, frames never break.

extension Material {
    /// Hit points in damage units (see `DamageModel`).
    var hp: Double {
        switch self {
        case .crystal: 1
        case .moonwood: 3
        case .meteorstone: 8
        case .frame: .infinity
        }
    }

    /// Contact impulses below this do nothing at all — resting weight and
    /// gentle bumps never chip a wall.
    var impactThreshold: Double {
        switch self {
        case .crystal: 2
        case .moonwood: 4
        case .meteorstone: 9
        case .frame: .infinity
        }
    }

    /// SpriteKit body density; heavier materials fall harder and resist pushes.
    var density: CGFloat {
        switch self {
        case .crystal: 0.6
        case .moonwood: 1.0
        case .meteorstone: 1.6
        case .frame: 2.0
        }
    }
}

enum DamageModel {
    /// Contact impulse → damage in HP units. Linear above the material's
    /// threshold so tuning stays predictable: one number (`damageScale`)
    /// controls how quickly force turns into destruction everywhere.
    static func damage(impulse: Double, against material: Material, multiplier: Double = 1) -> Double {
        guard material.impactThreshold.isFinite else { return 0 }
        return max(0, impulse - material.impactThreshold) / MoonshotTuning.damageScale * multiplier
    }
}

/// What a tapped ability does to damage, kept in Rules so it's testable
/// without SpriteKit: Zip's dash punches through the brittle tiers, Mochi's
/// slam hits everything harder.
enum AbilityEffects {
    static func damageMultiplier(for character: CharacterID, abilityActive: Bool, against material: Material) -> Double {
        guard abilityActive else { return 1 }
        switch character {
        case .mochi: return 2.5
        case .zip: return (material == .crystal || material == .moonwood) ? 2.0 : 1
        case .twinkle, .nox: return 1
        }
    }
}
