import Testing
@testable import OurApp

struct MoonshotMaterialsTests {
    @Test func impulseBelowThresholdDoesNothing() {
        #expect(DamageModel.damage(impulse: 1.9, against: .crystal) == 0)
        #expect(DamageModel.damage(impulse: 8.9, against: .meteorstone) == 0)
    }

    @Test func damageScalesAboveThreshold() {
        #expect(DamageModel.damage(impulse: 5, against: .crystal) == 1.0)      // (5-2)/3
        #expect(DamageModel.damage(impulse: 10, against: .moonwood) == 2.0)    // (10-4)/3
    }

    @Test func framesAreInvulnerable() {
        #expect(DamageModel.damage(impulse: 1000, against: .frame) == 0)
    }

    @Test func abilityMultipliers() {
        #expect(AbilityEffects.damageMultiplier(for: .zip, abilityActive: true, against: .crystal) == 2.0)
        #expect(AbilityEffects.damageMultiplier(for: .zip, abilityActive: true, against: .meteorstone) == 1.0)
        #expect(AbilityEffects.damageMultiplier(for: .zip, abilityActive: false, against: .crystal) == 1.0)
        #expect(AbilityEffects.damageMultiplier(for: .mochi, abilityActive: true, against: .meteorstone) == 2.5)
        #expect(AbilityEffects.damageMultiplier(for: .twinkle, abilityActive: true, against: .crystal) == 1.0)
    }

    @Test func crystalDiesToOneCleanHit() {
        let d = DamageModel.damage(impulse: 6, against: .crystal)
        #expect(d >= Material.crystal.hp)
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
