import Foundation
import SwiftData

/// The store's shape, version by version.
///
/// Until now the container was built from a bare `Schema([...])`, which leans
/// entirely on SwiftData's automatic *lightweight* migration. That copes with
/// adding an optional property and nothing else — rename one, retype one, or
/// remove one that data still depends on, and container creation throws. The
/// app calls `fatalError` there, so the failure isn't degraded behaviour, it is
/// an app that will not launch with the data stranded inside.
///
/// Establishing this with **one** game and nine types is cheap. With four games
/// it would not be, and there is a second deadline: **a CloudKit schema is
/// additive-only once deployed**, so anything awkward in the model shape is
/// frozen the day the sync milestone lands.
///
/// Unchanged types are referenced directly in both versions; only a type whose
/// shape actually differs needs a copy pinned to its old version.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [DecisionRecord.self, SchemaV1.SpecialDate.self, QuestionAnswer.self,
         Memory.self, CheckIn.self, MoonshotLevelResult.self,
         MoonshotCosmeticSetting.self, MoonshotCoachSeen.self,
         MoonshotMoondustEntry.self]
    }

    /// The shape *before* `emoji` was dropped. Pinned here so the migration can
    /// read the field on its way out — dropping a column in the same change
    /// that consumes it would destroy every icon anyone had picked.
    @Model
    final class SpecialDate {
        var id: UUID = UUID()
        var title: String = ""
        var emoji: String = "🎂"
        var iconID: String = ""
        var date: Date = Date.now
        var repeatsYearly: Bool = false
        var isAnniversary: Bool = false
        var updatedAt: Date = Date.now
        var authorID: String?
        var deletedAt: Date?

        /// Never called: this type exists only for the migration to read
        /// through. `@Model` insists on one all the same.
        init() {}
    }
}

/// `SpecialDate.emoji` is gone: it was superseded by `iconID` and has been
/// unread by the UI for several slices.
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [DecisionRecord.self, SpecialDate.self, QuestionAnswer.self,
         Memory.self, CheckIn.self, MoonshotLevelResult.self,
         MoonshotCosmeticSetting.self, MoonshotCoachSeen.self,
         MoonshotMoondustEntry.self]
    }
}

/// Current. Adds co-op: `CoopMatch` and `CoopTurn`.
///
/// Purely additive, so the stage is lightweight — but it is declared rather
/// than left implicit, because a plan that doesn't name a version refuses any
/// store carrying it (P30), and the next build would refuse this one.
enum SchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        SchemaV2.models + [CoopMatch.self, CoopTurn.self]
    }
}

/// Current. Adds the co-op ledger.
enum SchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }
    static var models: [any PersistentModel.Type] { SchemaV3.models + [CoopLevelResult.self] }
}

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self]
    }
    static var stages: [MigrationStage] { [dropRetiredEmoji, addCoop, addCoopLedger] }

    static let addCoopLedger = MigrationStage.lightweight(fromVersion: SchemaV3.self,
                                                          toVersion: SchemaV4.self)

    static let addCoop = MigrationStage.lightweight(fromVersion: SchemaV2.self,
                                                    toVersion: SchemaV3.self)

    /// Fills `iconID` from `emoji` for anything the old `DateIconMigration`
    /// hadn't reached, *then* lets the column go.
    ///
    /// This replaces that hand-rolled migration entirely. Running it at launch
    /// meant every launch paid for it and there was no way to express "this has
    /// happened, the field can go now" — which is exactly why `emoji` outlived
    /// its usefulness by several slices.
    /// The rule, lifted out of the stage so it stays testable — a
    /// `willMigrate` closure only runs during a real store transition, and the
    /// interesting part isn't the plumbing, it's which rows get touched.
    ///
    /// - Returns: the id to write, or `nil` to leave the row alone. A row that
    ///   already has an id carries a **choice the owner made**, and an emoji
    ///   that disagrees with it is stale — so the id always wins.
    static func backfilledIconID(existing: String, emoji: String) -> String? {
        guard existing.isEmpty else { return nil }
        return DateIcon.matching(emoji: emoji).rawValue
    }

    static let dropRetiredEmoji = MigrationStage.custom(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self,
        willMigrate: { context in
            let pending = try context.fetch(FetchDescriptor<SchemaV1.SpecialDate>())
            for row in pending {
                guard let filled = backfilledIconID(existing: row.iconID,
                                                    emoji: row.emoji) else { continue }
                row.iconID = filled
            }
            try context.save()
        },
        didMigrate: nil)
}
