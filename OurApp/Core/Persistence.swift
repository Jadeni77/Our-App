import Foundation
import OSLog
import SwiftData

/// Core persistence: the one place the app assembles its SwiftData container.
/// Modules contribute their @Model types to the schema here — they never build
/// their own containers.
enum Persistence {
    /// `url` is injectable so a test can hand it a store written by an older
    /// schema — which is the only way to reproduce the failure below without a
    /// phone that has been carrying one since July.
    static func makeContainer(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        // The schema is whatever the newest version says it is, and the plan
        // is how a store written by an older build gets there. Adding a model
        // type means adding it to the newest `SchemaVn`, not here.
        let schema = Schema(versionedSchema: SchemaV4.self)
        // **Explicit, not left to `.automatic` by omission.** The default flips
        // CloudKit mirroring on the moment the app carries an iCloud
        // entitlement — which is how adding that entitlement turned every
        // non-defaulted attribute into a store that refuses to load, and
        // `OurAppApp` turns that into a `fatalError`. Twenty attributes across
        // five models were offenders; the four couples types were clean only
        // because §7 hygiene had been applied to them and nowhere else.
        //
        // Mirroring to the *private* database is what we want in the end: it is
        // the couple's own backup, and it is what makes "delete the app and get
        // everything back" work with no login screen. Sharing between two
        // different Apple IDs stays with our own transport, because mirroring
        // cannot cross accounts.
        //
        // In-memory stores get `.none` because mirroring needs a real store —
        // which is also why the regular suite could never have caught the
        // problem above, and why `CloudKitSchemaTests` writes to disk.
        let configuration = url.map {
            ModelConfiguration(schema: schema, url: $0, cloudKitDatabase: .none)
        } ?? ModelConfiguration(schema: schema,
                                isStoredInMemoryOnly: inMemory,
                                cloudKitDatabase: inMemory ? .none : .automatic)
        do {
            return try ModelContainer(for: schema,
                                      migrationPlan: AppMigrationPlan.self,
                                      configurations: [configuration])
        } catch {
            // **A store from before the versions existed must not brick the
            // app.** Declaring a migration plan makes SwiftData refuse any
            // store whose model version isn't one it names — "Cannot use staged
            // migration with an unknown model version" — and `OurAppApp` turns
            // that into a `fatalError`. Before the plan existed, automatic
            // lightweight migration handled those stores happily.
            //
            // Found on a real phone carrying a store from an older build, which
            // is the only place it *could* be found: every simulator store had
            // been created by a current build.
            //
            // So: try the plan, and if the store predates it, fall back to
            // letting SwiftData migrate the old way. Strictly better than
            // crashing, and it only runs when the plan has already refused.
            Logger(subsystem: "OurApp", category: "persistence")
                .error("staged migration refused the store, falling back to lightweight: \(error.localizedDescription)")
            return try ModelContainer(for: schema, configurations: [configuration])
        }
    }
}
