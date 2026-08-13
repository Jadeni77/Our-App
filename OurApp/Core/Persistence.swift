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
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema,
                                  migrationPlan: AppMigrationPlan.self,
                                  configurations: [configuration])
    }
}
