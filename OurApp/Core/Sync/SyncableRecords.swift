import Foundation
import SwiftData

/// Every record type that travels, each spelling out what it sends.
///
/// Kept in one file rather than scattered across the model definitions: this is
/// the wire format, and seeing them together is how you notice that one of them
/// forgot a field. The matching `apply` rules live in `SyncApply.swift`, one
/// function per type.
///
/// **There is no registry.** A type syncs because `SyncEngine.push` collects it
/// and `SyncApply.apply` has a case for it — those two lists are the whole
/// mechanism, and both are in `Core/Sync`. A `SyncRegistry` enum used to sit
/// here claiming otherwise; it had zero call sites, named four of the twelve
/// types, and its comment told whoever added the next model to register it in a
/// place that did nothing.
///
/// **Deliberate omissions**, so they read as decisions rather than oversights:
/// `SpecialDate.emoji` (retired, and owed for deletion once the icon migration
/// has run on both phones), and `Memory.photoIDs`' actual bytes — the ids
/// travel, the files arrive in slice B.

extension SpecialDate: SyncableRecord {
    static var syncTypeName: String { "SpecialDate" }
    static var syncCategory: SyncCategory { .shared }

    var syncID: UUID { id }
    var syncAuthorID: String { authorID ?? "" }
    var syncUpdatedAt: Date { updatedAt }
    var syncDeletedAt: Date? { deletedAt }

    func syncFields() -> [String: SyncValue] {
        ["title": .string(title),
         "iconID": .string(iconID),
         "date": .date(date),
         "repeatsYearly": .bool(repeatsYearly),
         "isAnniversary": .bool(isAnniversary)]
    }
}

extension QuestionAnswer: SyncableRecord {
    static var syncTypeName: String { "QuestionAnswer" }
    static var syncCategory: SyncCategory { .shared }

    var syncID: UUID { id }
    var syncAuthorID: String { authorID }
    var syncUpdatedAt: Date { updatedAt }
    var syncDeletedAt: Date? { deletedAt }

    func syncFields() -> [String: SyncValue] {
        ["questionID": .string(questionID),
         "day": .date(day),
         "text": .string(text)]
    }
}

extension Memory: SyncableRecord {
    static var syncTypeName: String { "Memory" }
    static var syncCategory: SyncCategory { .shared }

    var syncID: UUID { id }
    var syncAuthorID: String { authorID }
    var syncUpdatedAt: Date { updatedAt }
    var syncDeletedAt: Date? { deletedAt }

    func syncFields() -> [String: SyncValue] {
        var fields: [String: SyncValue] = ["note": .string(note),
                                           "photoIDs": .stringArray(photoIDs)]
        // Optional day (H23): absent means undated, which is different from a
        // sentinel date and must survive the round trip as absent.
        if let day { fields["day"] = .date(day) }
        return fields
    }
}

extension CheckIn: SyncableRecord {
    static var syncTypeName: String { "CheckIn" }
    static var syncCategory: SyncCategory { .shared }

    var syncID: UUID { id }
    var syncAuthorID: String { authorID }
    var syncUpdatedAt: Date { updatedAt }
    var syncDeletedAt: Date? { deletedAt }

    func syncFields() -> [String: SyncValue] {
        ["day": .date(day)]
    }
}

/// Campaign progress is **mirrored**, not shared (P20): each phone owns its own
/// rows, the other stores and displays them, and neither ever writes the
/// other's. Two authors therefore never touch one record, so no conflict is
/// possible — which is the guarantee the owner asked for when they said the
/// regular mode doesn't share.
extension MoonshotLevelResult: SyncableRecord {
    static var syncTypeName: String { "MoonshotLevelResult" }
    static var syncCategory: SyncCategory { .mirrored }

    var syncID: UUID { id }
    var syncAuthorID: String { partnerID }
    var syncUpdatedAt: Date { updatedAt }
    /// No tombstone: progress is never deleted, only improved on.
    var syncDeletedAt: Date? { nil }

    func syncFields() -> [String: SyncValue] {
        ["levelID": .string(levelID.uuidString),
         "modeRaw": .string(modeRaw),
         "cleared": .bool(cleared),
         "bestStars": .int(bestStars),
         "bestFlings": .int(bestFlings),
         "featOneFling": .bool(featOneFling),
         "featNoAbility": .bool(featNoAbility),
         "featCleanSweep": .bool(featCleanSweep)]
    }
}

/// **Mirrored, not shared.** Each person owns their own profile row; the other
/// phone displays it and never writes it. Two authors never touch one record,
/// so there is nothing to merge — a stronger guarantee than the LWW the shared
/// types need, and the reason "whose name is this?" has an answer in the data.
extension Profile: SyncableRecord {
    static var syncTypeName: String { "Profile" }
    static var syncCategory: SyncCategory { .mirrored }

    var syncID: UUID { id }
    var syncAuthorID: String { authorID }
    var syncUpdatedAt: Date { updatedAt }
    var syncDeletedAt: Date? { deletedAt }

    func syncFields() -> [String: SyncValue] {
        var fields: [String: SyncValue] = [
            "name": .string(name),
            "pronoun": .string(pronoun),
        ]
        if let photoID { fields["photoID"] = .string(photoID) }
        return fields
    }
}

/// Co-op is **shared**: one match, both people writing into it.
extension CoopMatch: SyncableRecord {
    static var syncTypeName: String { "CoopMatch" }
    static var syncCategory: SyncCategory { .shared }

    var syncID: UUID { id }
    /// The turn holder is who last moved it, which is what LWW should break on.
    var syncAuthorID: String { turnHolder }
    var syncUpdatedAt: Date { updatedAt }
    var syncDeletedAt: Date? { deletedAt }

    func syncFields() -> [String: SyncValue] {
        var fields: [String: SyncValue] = [
            "levelID": .string(levelID.uuidString),
            "participants": .stringArray(participants),
            "turnHolder": .string(turnHolder),
            "turnIndex": .int(turnIndex),
            "boardState": .string(boardState.base64EncodedString()),
        ]
        if let finishedAt { fields["finishedAt"] = .date(finishedAt) }
        return fields
    }
}

/// Append-only, so it never conflicts — a union, not a merge.
extension CoopTurn: SyncableRecord {
    static var syncTypeName: String { "CoopTurn" }
    static var syncCategory: SyncCategory { .shared }

    var syncID: UUID { id }
    var syncAuthorID: String { authorID }
    var syncUpdatedAt: Date { updatedAt }
    var syncDeletedAt: Date? { deletedAt }

    func syncFields() -> [String: SyncValue] {
        ["matchID": .string(matchID.uuidString),
         "index": .int(index),
         "clip": .string(clip.base64EncodedString()),
         "resultingState": .string(resultingState.base64EncodedString())]
    }
}

/// **Shared, and merged toward the best run rather than last-writer-wins.**
/// One row per level for the couple — its id *is* the level id, so two phones
/// finishing independently converge instead of creating two rows.
extension CoopLevelResult: SyncableRecord {
    static var syncTypeName: String { "CoopLevelResult" }
    static var syncCategory: SyncCategory { .shared }

    var syncID: UUID { id }
    /// No single author: the row belongs to the couple. Constant so the LWW
    /// tiebreak can never pick a winner on it — the merge below is what
    /// decides, and it does so without needing one.
    var syncAuthorID: String { "couple" }
    var syncUpdatedAt: Date { updatedAt }
    var syncDeletedAt: Date? { deletedAt }

    func syncFields() -> [String: SyncValue] {
        ["cleared": .bool(cleared),
         "bestStars": .int(bestStars),
         "bestFlings": .int(bestFlings),
         "featOneFling": .bool(featOneFling),
         "featNoAbility": .bool(featNoAbility),
         "featCleanSweep": .bool(featCleanSweep)]
    }
}

/// **Shared.** A library both of you add to.
extension Photo: SyncableRecord {
    static var syncTypeName: String { "Photo" }
    static var syncCategory: SyncCategory { .shared }

    var syncID: UUID { id }
    var syncAuthorID: String { authorID }
    var syncUpdatedAt: Date { updatedAt }
    var syncDeletedAt: Date? { deletedAt }

    func syncFields() -> [String: SyncValue] {
        var fields: [String: SyncValue] = [
            "assetID": .string(assetID),
            "caption": .string(caption),
            "addedAt": .date(addedAt),
        ]
        if let takenAt { fields["takenAt"] = .date(takenAt) }
        return fields
    }
}

extension Album: SyncableRecord {
    static var syncTypeName: String { "Album" }
    static var syncCategory: SyncCategory { .shared }

    var syncID: UUID { id }
    var syncAuthorID: String { authorID }
    var syncUpdatedAt: Date { updatedAt }
    var syncDeletedAt: Date? { deletedAt }

    func syncFields() -> [String: SyncValue] {
        var fields: [String: SyncValue] = [
            "name": .string(name),
            "caption": .string(caption),
            "createdAt": .date(createdAt),
        ]
        if let coverAssetID { fields["coverAssetID"] = .string(coverAssetID) }
        return fields
    }
}

extension AlbumEntry: SyncableRecord {
    static var syncTypeName: String { "AlbumEntry" }
    static var syncCategory: SyncCategory { .shared }

    var syncID: UUID { id }
    var syncAuthorID: String { authorID }
    var syncUpdatedAt: Date { updatedAt }
    var syncDeletedAt: Date? { deletedAt }

    func syncFields() -> [String: SyncValue] {
        ["albumID": .string(albumID.uuidString),
         "assetID": .string(assetID),
         "addedAt": .date(addedAt)]
    }
}
