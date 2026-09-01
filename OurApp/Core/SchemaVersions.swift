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

/// Adds the co-op ledger.
enum SchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }
    static var models: [any PersistentModel.Type] { SchemaV3.models + [CoopLevelResult.self] }
}

/// Adds profiles, so each person's name and photo comes from their own phone
/// instead of being typed on the other's.
enum SchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }
    static var models: [any PersistentModel.Type] { SchemaV4.models + [Profile.self] }
}

/// Adds albums: a photo library, named collections, and the memberships that
/// put one in the other.
enum SchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }
    static var models: [any PersistentModel.Type] {
        SchemaV5.models + [Photo.self, SchemaV6.Album.self, AlbumEntry.self]
    }

    /// The shape *before* `caption` existed. Pinned here for the same reason
    /// `SchemaV1.SpecialDate` is pinned above: `Album` genuinely differs
    /// between this version and the next, and a schema chain where two
    /// adjacent versions resolve to byte-identical model shapes is one
    /// SwiftData refuses outright — "Duplicate version checksums detected",
    /// an uncaught Objective-C exception that the `do`/`catch` fallback in
    /// `Persistence.makeContainer` (P30) cannot intercept — rather than a
    /// distinction that can be left to the live type.
    ///
    /// **This pin is asserted, not verified.** Nothing in the suite checks it
    /// against bytes an older build actually wrote — `AlbumCaptionMigrationTests`
    /// seeds its "V6 store" through `Schema(versionedSchema: SchemaV6.self)`,
    /// i.e. through this very declaration, so it can only prove *this shape*
    /// migrates cleanly to V7, never that this shape matches what V6 shipped.
    /// Delete `coverAssetID` below and the whole suite still passes. Harmless
    /// today because `addAlbumCaption` is `.lightweight`: a wrong pin just
    /// makes staged migration refuse the store and fall back to plan-less
    /// lightweight migration, same as any unrecognised version, no data lost.
    /// It stops being harmless the day a stage between two pinned versions is
    /// `.custom` — exactly `dropRetiredEmoji`'s shape below, whose
    /// `willMigrate` backfills `iconID` before dropping `emoji`. A mis-pinned
    /// `fromVersion` there means staged migration is refused, the fallback
    /// runs plan-less, and `willMigrate` is **silently skipped** — destroying
    /// every icon anyone picked, with the suite fully green throughout. See
    /// P32.
    @Model
    final class Album {
        var id: UUID = UUID()
        var name: String = ""
        var coverAssetID: String?
        var authorID: String = ""
        var createdAt: Date = Date.now
        var updatedAt: Date = Date.now
        var deletedAt: Date?

        init(name: String, authorID: String) {
            self.id = UUID()
            self.name = name
            self.authorID = authorID
            self.createdAt = .now
            self.updatedAt = .now
        }
    }
}

/// Current. Adds `Album.caption`: the couple's own line about the album,
/// alongside its cover and name.
///
/// No new entry in `models` beyond swapping the pinned V6 `Album` back for the
/// live one — `Album` itself already carries the shape this version wants,
/// which is why nothing else needed a bump.
enum SchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(7, 0, 0) }
    static var models: [any PersistentModel.Type] {
        SchemaV5.models + [Photo.self, Album.self, AlbumEntry.self]
    }
}

/// The one name for "whichever `SchemaVn` is current."
///
/// `Persistence.swift` builds the real container from this, and
/// `CloudKitSchemaTests` checks CloudKit-mirroring legality against this — the
/// same alias, so the two can never drift apart. Before this existed, both
/// sides spelled out a literal `SchemaVn`, and bumping the schema meant
/// remembering to re-aim both by hand. Nobody did, twice: `CloudKitSchemaTests`
/// was still checking `SchemaV4` after V5 and V6 had already shipped, so the
/// one test whose entire purpose is catching a non-defaulted attribute before
/// it reaches a device with an iCloud entitlement — the exact failure that
/// once bricked this app — was quietly checking nothing about either.
///
/// Bumping the schema now means adding `SchemaVn+1` and moving this line;
/// there is nowhere else that needs to change.
typealias CurrentSchema = SchemaV7

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self, SchemaV6.self,
         SchemaV7.self]
    }
    static var stages: [MigrationStage] {
        [dropRetiredEmoji, addCoop, addCoopLedger, addProfiles, addAlbums, addAlbumCaption]
    }

    /// Lightweight: one new property, defaulted, on a model that already
    /// exists. Nothing taken away from what is already stored.
    static let addAlbumCaption = MigrationStage.lightweight(fromVersion: SchemaV6.self,
                                                            toVersion: SchemaV7.self)

    /// Lightweight: three new models, every property defaulted, nothing taken
    /// away from what is already stored.
    static let addAlbums = MigrationStage.lightweight(fromVersion: SchemaV5.self,
                                                      toVersion: SchemaV6.self)

    /// Lightweight: adding a model with every property defaulted takes nothing
    /// away and asks nothing of what is already stored.
    static let addProfiles = MigrationStage.lightweight(fromVersion: SchemaV4.self,
                                                        toVersion: SchemaV5.self)

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
