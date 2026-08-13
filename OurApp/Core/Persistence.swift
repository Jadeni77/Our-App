import Foundation
import SwiftData

/// Core persistence: the one place the app assembles its SwiftData container.
/// Modules contribute their @Model types to the schema here — they never build
/// their own containers.
enum Persistence {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        // The schema is whatever the newest version says it is, and the plan
        // is how a store written by an older build gets there. Adding a model
        // type means adding it to `SchemaV2`, not here.
        let schema = Schema(versionedSchema: SchemaV2.self)
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
        let configuration = ModelConfiguration(schema: schema,
                                               isStoredInMemoryOnly: inMemory,
                                               cloudKitDatabase: inMemory ? .none : .automatic)
        return try ModelContainer(for: schema,
                                  migrationPlan: AppMigrationPlan.self,
                                  configurations: [configuration])
    }
}
