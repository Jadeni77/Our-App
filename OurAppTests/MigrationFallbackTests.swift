import Foundation
import SwiftData
import Testing
@testable import OurApp

/// A store written before `SchemaV1` existed must still open.
///
/// Declaring a `SchemaMigrationPlan` makes SwiftData refuse any store whose
/// model version isn't one the plan names — *"Cannot use staged migration with
/// an unknown model version"* — and `OurAppApp` turns that into a `fatalError`.
/// Before the plan existed, automatic lightweight migration handled those
/// stores without complaint. So introducing versioning **created** a way for
/// old installs to stop launching.
///
/// It was found on a real phone carrying a store from July, and it could only
/// have been found there: every simulator store had been created by a current
/// build, so nothing in the suite had an old version to refuse.
@MainActor
struct MigrationFallbackTests {
    @Test func aStoreFromBeforeTheVersionsExistedStillOpens() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: url.appendingPathExtension(suffix.isEmpty ? "" : String(suffix.dropFirst())))
            }
            try? FileManager.default.removeItem(at: url)
        }

        // A store the plan has never heard of: one entity, no version identity
        // it recognises. This is the shape the phone had — `DecisionRecord`
        // alone, from before Special Dates or Memories existed.
        let ancient = Schema([DecisionRecord.self])
        let seeded = try ModelContainer(
            for: ancient,
            configurations: [ModelConfiguration(schema: ancient, url: url, cloudKitDatabase: .none)])
        let context = ModelContext(seeded)
        context.insert(DecisionRecord(date: .now, cuisineChosen: "ramen"))
        try context.save()

        // Opening it with the real plan must succeed — via the fallback, since
        // staged migration refuses it — and must not lose what was there.
        let migrated = try Persistence.makeContainer(url: url)
        let read = ModelContext(migrated)
        #expect(try read.fetchCount(FetchDescriptor<DecisionRecord>()) == 1)
        // And the entities that didn't exist back then are usable now.
        read.insert(Memory(note: "after migrating", day: .now,
                           authorID: "me", photoIDs: ["a"]))
        try read.save()
        #expect(try read.fetchCount(FetchDescriptor<Memory>()) == 1)
    }
}
