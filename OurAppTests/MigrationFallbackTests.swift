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

/// The V5 → V6 stage, on a store that already carries real rows.
///
/// `MigrationFallbackTests` above does **not** cover this and cannot: it hands
/// the plan a store with no version identity the plan recognises, which staged
/// migration refuses outright, so that test only ever exercises the plan-less
/// fallback. Every stage between V1 and V6 was therefore uncovered — including
/// the one that ships albums onto a phone holding pictures the owner cares
/// about, which the design named as its own risk (§7).
@MainActor
struct AlbumMigrationTests {
    /// A V5 store on disk, with rows in it worth losing — the shape a phone was
    /// carrying the day before albums existed.
    private func seededV5Store() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("v5-\(UUID().uuidString).store")
        let v5 = Schema(versionedSchema: SchemaV5.self)
        let seeded = try ModelContainer(
            for: v5,
            configurations: [ModelConfiguration(schema: v5, url: url, cloudKitDatabase: .none)])
        let writing = ModelContext(seeded)
        writing.insert(Memory(note: "before albums", day: .now,
                              authorID: "me", photoIDs: ["a"]))
        writing.insert(Profile(authorID: "me", name: "橘子"))
        try writing.save()
        return url
    }

    private func remove(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    /// The guarantee the owner cares about: the pictures survive the upgrade.
    @Test func aV5StoreOpensAtV6WithItsRowsIntact() throws {
        let url = try seededV5Store()
        defer { remove(url) }

        // The app's own container builder, so this is the path a real launch
        // takes rather than a hand-built one.
        let migrated = try Persistence.makeContainer(url: url)
        let read = ModelContext(migrated)
        #expect(try read.fetchCount(FetchDescriptor<Memory>()) == 1)
        #expect(try read.fetchCount(FetchDescriptor<Profile>()) == 1)
        #expect(try read.fetch(FetchDescriptor<Memory>()).first?.note == "before albums")
        #expect(try read.fetch(FetchDescriptor<Profile>()).first?.name == "橘子")

        // And what V6 added is usable on the migrated store.
        let album = Album(name: "🎀", authorID: "me")
        read.insert(album)
        read.insert(Photo(assetID: "a", authorID: "me"))
        read.insert(AlbumEntry(albumID: album.id, assetID: "a", authorID: "me"))
        try read.save()
        #expect(AlbumStore.count(of: album, in: read) == 1)
    }

    /// **The stage itself, with the fallback taken away.**
    ///
    /// `Persistence.makeContainer` catches a refusal from staged migration and
    /// retries without a plan, which is what stops an old store bricking the
    /// app — and which also means the test above passes with `addAlbums`
    /// deleted from the plan entirely. Verified by doing exactly that: it went
    /// green down the fallback. So this one builds the container the plan's
    /// own way, where a missing or broken V5 → V6 stage is a thrown error
    /// rather than a quieter route to the same place.
    @Test func theV5ToV6StageAcceptsAV5StoreWithNoFallback() throws {
        let url = try seededV5Store()
        defer { remove(url) }

        let schema = Schema(versionedSchema: CurrentSchema.self)
        let migrated = try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, url: url,
                                                cloudKitDatabase: .none)])
        let read = ModelContext(migrated)
        #expect(try read.fetchCount(FetchDescriptor<Memory>()) == 1)
        #expect(try read.fetchCount(FetchDescriptor<Profile>()) == 1)
    }
}
