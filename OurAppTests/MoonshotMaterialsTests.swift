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
}
