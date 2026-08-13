import Foundation
import SwiftData
import Testing
@testable import OurApp

/// Guards the one schema rule that isn't visible in Swift: **CloudKit
/// integration requires every attribute to be optional or carry a default.**
///
/// This is not hypothetical. Adding the iCloud entitlement flipped SwiftData's
/// `.automatic` mode on and the store stopped loading — twenty attributes
/// across five models were non-optional with no default. `OurAppApp` turns a
/// failed container into a `fatalError`, so the app would simply not have
/// launched, and it would have happened the day the Developer Program
/// enrolment activated rather than on any commit.
///
/// The regular suite can't catch it: those containers are in-memory, and
/// mirroring needs a real store. So this one writes to disk.
@MainActor
struct CloudKitSchemaTests {
    @Test func everyAttributeIsCloudKitLegal() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloudkit-check-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = Schema(versionedSchema: SchemaV4.self)
        let configuration = ModelConfiguration(schema: schema, url: url,
                                               cloudKitDatabase: .automatic)
        // Throws if any attribute is non-optional without a default. Not
        // signed into iCloud is fine and expected — that surfaces later, as a
        // recoverable account error, long after this validation has run.
        _ = try ModelContainer(for: schema,
                               migrationPlan: AppMigrationPlan.self,
                               configurations: [configuration])
    }
}
