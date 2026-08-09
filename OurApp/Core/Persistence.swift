import Foundation
import SwiftData

/// Core persistence: the one place the app assembles its SwiftData container.
/// Modules contribute their @Model types to the schema here — they never build
/// their own containers.
enum Persistence {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            DecisionRecord.self,
            SpecialDate.self,
            QuestionAnswer.self,
            MoonshotLevelResult.self,
            MoonshotCosmeticSetting.self,
            MoonshotCoachSeen.self,
            MoonshotMoondustEntry.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
