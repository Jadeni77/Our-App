import Foundation

/// Material physics + the impulse damage model (M7): a readable destruction
/// hierarchy — crystal shatters, moonwood cracks then splinters, meteorstone
/// shrugs off everything but slams and the gravity well, frames never break.

extension Material {
    /// Hit points in damage units (see `DamageModel`). Calibrated at floaty
    /// gravity (full-pull mochi ≈ 8.6 impulse units, twinkle ≈ 4.8, zip
    /// ≈ 3.7 with his ×2 dash as the wall-breaker): crystal dies to one
    /// clean hit from anyone but plain zip, moonwood cracks then breaks on
    /// the second mochi, meteorstone shrugs off birds entirely — slams
    /// (≈ 17) and the well are its counters (M7).
    var hp: Double {
        switch self {
        case .crystal: 1
        case .moonwood: 3.5
        case .meteorstone: 7   // two slams, decisively — 6 straddled one-slam-lethal
        case .cloudfoam: 2     // springy, not invincible: two determined mochis burst it
        case .frame: .infinity
        }
    }

    /// Contact impulses below this do nothing at all — resting weight,
    /// gentle bumps, and most cascading debris never chip a wall.
    var impactThreshold: Double {
        switch self {
        case .crystal: 1.5
        case .moonwood: 3
        case .meteorstone: 10
        case .cloudfoam: 4     // bounces shrug; only solid direct hits wound it
        case .frame: .infinity
        }
    }

    /// SpriteKit body density; heavier materials fall harder and resist pushes.
    var density: CGFloat {
        switch self {
        case .crystal: 0.6
        case .moonwood: 1.0
        case .meteorstone: 1.6
        case .cloudfoam: 0.4   // it's a cloud
        case .frame: 2.0
        }
    }

    /// Body restitution (M20): Cloudfoam is the springboard; everything
    /// else stays inert so forts don't jitter.
    var restitution: CGFloat {
        switch self {
        case .cloudfoam: 0.85
        case .crystal, .moonwood, .meteorstone, .frame: 0.05
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

/// Gloom toughness (device-pass ruling: they must not die to a touch).
/// Returns hit points of damage for a contact impulse: 0 = shrug,
/// 1 = bruise, 2 = pop outright.
enum GloomDamage {
    static func hits(forImpulse impulse: Double) -> Int {
        // Full HP at the instant tier: "a clean hit one-shots" must survive
        // any future gloomHP retune.
        if impulse >= MoonshotTuning.gloomInstantPopImpulse { return MoonshotTuning.gloomHP }
        if impulse >= MoonshotTuning.gloomBruiseImpulse { return 1 }
        return 0
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
        case .twinkle, .nox, .misty: return 1
        }
    }
}
