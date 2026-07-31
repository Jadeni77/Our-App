import Testing
@testable import OurApp

struct MoonshotMaterialsTests {
    @Test func impulseBelowThresholdDoesNothing() {
        for material in [Material.crystal, .moonwood, .meteorstone] {
            #expect(DamageModel.damage(impulse: material.impactThreshold - 0.1, against: material) == 0)
        }
    }

    @Test func damageScalesAboveThreshold() {
        // One damageScale worth of impulse over the threshold = exactly 1 HP.
        for material in [Material.crystal, .moonwood, .meteorstone] {
            let impulse = material.impactThreshold + MoonshotTuning.damageScale
            #expect(DamageModel.damage(impulse: impulse, against: material) == 1.0)
        }
    }

    @Test func framesAreInvulnerable() {
        #expect(DamageModel.damage(impulse: 1000, against: .frame) == 0)
    }

    @Test func cloudfoamBouncesButBreaksToDeterminedHits() {
        #expect(Material.cloudfoam.restitution >= 0.8)          // the springboard
        for material in [Material.crystal, .moonwood, .meteorstone, .frame] {
            #expect(material.restitution <= 0.1)                 // everyone else stays inert
        }
        // A full-pull mochi (≈8.6) hurts it but doesn't one-shot; two hits kill.
        let direct = DamageModel.damage(impulse: 8.6, against: .cloudfoam)
        #expect(direct > 0 && direct < Material.cloudfoam.hp)
        #expect(direct * 2 >= Material.cloudfoam.hp)
    }

    @Test func theDestructionHierarchyHoldsAtDirectHitStrength() {
        // A full-pull mochi lands ≈ 8.6 impulse units at floaty gravity:
        // crystal must die, moonwood must be hurt but survive, and
        // meteorstone must not care. The teaching arc depends on this.
        let directHit = 8.6
        #expect(DamageModel.damage(impulse: directHit, against: .crystal) >= Material.crystal.hp)
        let woodDamage = DamageModel.damage(impulse: directHit, against: .moonwood)
        #expect(woodDamage > 0 && woodDamage < Material.moonwood.hp)
        #expect(DamageModel.damage(impulse: directHit, against: .meteorstone) == 0)
    }

    @Test func abilityMultipliers() {
        #expect(AbilityEffects.damageMultiplier(for: .zip, abilityActive: true, against: .crystal) == 2.0)
        #expect(AbilityEffects.damageMultiplier(for: .zip, abilityActive: true, against: .meteorstone) == 1.0)
        #expect(AbilityEffects.damageMultiplier(for: .zip, abilityActive: false, against: .crystal) == 1.0)
        #expect(AbilityEffects.damageMultiplier(for: .mochi, abilityActive: true, against: .meteorstone) == 2.5)
        #expect(AbilityEffects.damageMultiplier(for: .twinkle, abilityActive: true, against: .crystal) == 1.0)
    }

    @Test func gloomsShrugGrazesBruiseOnSolidHitsPopOnDirectOnes() {
        // Owners' device-pass ruling: Angry-Birds pigs don't die to a touch.
        #expect(GloomDamage.hits(forImpulse: MoonshotTuning.gloomBruiseImpulse - 0.1) == 0)
        #expect(GloomDamage.hits(forImpulse: MoonshotTuning.gloomBruiseImpulse) == 1)
        #expect(GloomDamage.hits(forImpulse: MoonshotTuning.gloomInstantPopImpulse - 0.1) == 1)
        // The one-shot invariant: an instant-tier hit deals full HP,
        // whatever gloomHP is tuned to.
        #expect(GloomDamage.hits(forImpulse: MoonshotTuning.gloomInstantPopImpulse)
                >= MoonshotTuning.gloomHP)
    }

    @Test func twoBruisesEqualOneGloom() {
        #expect(GloomDamage.hits(forImpulse: MoonshotTuning.gloomBruiseImpulse) * 2
                >= MoonshotTuning.gloomHP)
    }
}
