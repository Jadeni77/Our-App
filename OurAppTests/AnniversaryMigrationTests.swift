import Foundation
import SwiftData
import Testing
@testable import OurApp

@MainActor
struct AnniversaryMigrationTests {
    /// A scratch suite per test, wiped first — the pattern CoupleIdentityTests uses.
    private func makeDefaults(_ suite: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func anniversaryCount(_ context: ModelContext) throws -> Int {
        try context.fetchCount(
            FetchDescriptor<SpecialDate>(predicate: SpecialDate.anniversary))
    }

    @Test func movesAStoredAnniversaryIntoARecord() throws {
        let defaults = makeDefaults("migration.moves")
        let stored = Date(timeIntervalSinceReferenceDate: 700_000_000)
        defaults.set(stored.timeIntervalSinceReferenceDate,
                     forKey: AnniversaryMigration.legacyKey)

        let container = try Persistence.makeContainer(inMemory: true)
        AnniversaryMigration.runIfNeeded(in: container, defaults: defaults)

        let context = ModelContext(container)
        let rows = try context.fetch(
            FetchDescriptor<SpecialDate>(predicate: SpecialDate.anniversary))
        #expect(rows.count == 1)
        #expect(rows.first?.repeatsYearly == true)

        // Asserted as the invariant, not as a round trip. Comparing the stored
        // civil day against `localDay` passes whether or not the anchor was
        // applied at all in any timezone west of UTC+4 — including this
        // machine's — so it would not notice the anchor being dropped.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        #expect(utc.component(.hour, from: rows[0].date) == 12)
        #expect(rows[0].date == SpecialDateSchedule.anchor(for: stored))

        // The legacy value is gone, so there is one truth afterwards.
        #expect(defaults.object(forKey: AnniversaryMigration.legacyKey) == nil)
    }

    @Test func isIdempotent() throws {
        let defaults = makeDefaults("migration.idempotent")
        defaults.set(Date.now.timeIntervalSinceReferenceDate,
                     forKey: AnniversaryMigration.legacyKey)

        let container = try Persistence.makeContainer(inMemory: true)
        AnniversaryMigration.runIfNeeded(in: container, defaults: defaults)

        // Put the key back before the second run. Without this the second call
        // returns at the first guard and the "key present, row present" path —
        // the one this test is named for — is never reached.
        defaults.set(Date.now.timeIntervalSinceReferenceDate,
                     forKey: AnniversaryMigration.legacyKey)
        AnniversaryMigration.runIfNeeded(in: container, defaults: defaults)

        #expect(try anniversaryCount(ModelContext(container)) == 1)
        #expect(defaults.object(forKey: AnniversaryMigration.legacyKey) == nil)
    }

    @Test func keepsTheLegacyKeyWhenTheSaveFails() throws {
        struct SaveFailed: Error {}
        let defaults = makeDefaults("migration.savefails")
        defaults.set(Date.now.timeIntervalSinceReferenceDate,
                     forKey: AnniversaryMigration.legacyKey)

        let container = try Persistence.makeContainer(inMemory: true)
        AnniversaryMigration.runIfNeeded(in: container, defaults: defaults) { _ in
            throw SaveFailed()
        }

        // The whole no-loss argument rests on this: a failed write must leave
        // the old value in place so the next launch can try again.
        #expect(defaults.object(forKey: AnniversaryMigration.legacyKey) != nil)
    }

    @Test func aTombstonedAnniversaryIsNotFoundByTheLookup() throws {
        // The `deletedAt == nil` half of `SpecialDate.anniversary` decides
        // whether Home's counter survives a delete, and whether a new
        // anniversary can be created afterwards. Nothing else pins it.
        let container = try Persistence.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let anniversary = SpecialDate(title: "", date: SpecialDateSchedule.anchor(for: .now),
                                      repeatsYearly: true, isAnniversary: true)
        context.insert(anniversary)
        try context.save()
        #expect(try anniversaryCount(context) == 1)

        anniversary.deletedAt = .now
        try context.save()

        #expect(try anniversaryCount(context) == 0)
    }

    @Test func doesNothingWhenNoAnniversaryWasEverSet() throws {
        let defaults = makeDefaults("migration.absent")
        let container = try Persistence.makeContainer(inMemory: true)

        AnniversaryMigration.runIfNeeded(in: container, defaults: defaults)

        #expect(try anniversaryCount(ModelContext(container)) == 0)
    }

    @Test func doesNotAddASecondRowWhenOneAlreadyExists() throws {
        let defaults = makeDefaults("migration.existing")
        defaults.set(Date.now.timeIntervalSinceReferenceDate,
                     forKey: AnniversaryMigration.legacyKey)

        let container = try Persistence.makeContainer(inMemory: true)
        let seeding = ModelContext(container)
        let anchored = SpecialDateSchedule.anchor(for: .now)
        seeding.insert(SpecialDate(title: "", date: anchored,
                                   repeatsYearly: true, isAnniversary: true))
        try seeding.save()

        AnniversaryMigration.runIfNeeded(in: container, defaults: defaults)

        let rows = try ModelContext(container).fetch(
            FetchDescriptor<SpecialDate>(predicate: SpecialDate.anniversary))
        #expect(rows.count == 1)
        // The record wins: overwriting it with the legacy value would satisfy a
        // count-only assertion while quietly changing the couple's date.
        #expect(rows.first?.date == anchored)
        #expect(defaults.object(forKey: AnniversaryMigration.legacyKey) == nil)
    }
}
