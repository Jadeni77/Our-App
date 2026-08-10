import Foundation
import SwiftData

/// Applying one envelope to the local store. Every merge rule lives here, and
/// nowhere else.
@MainActor
enum SyncApply {
    /// - Returns: whether the local store changed, so callers can skip a save.
    @discardableResult
    static func apply(_ envelope: SyncEnvelope,
                      in context: ModelContext,
                      localAuthorID: String) -> Bool {
        switch envelope.recordType {
        case SpecialDate.syncTypeName: applySpecialDate(envelope, in: context)
        case QuestionAnswer.syncTypeName: applyQuestionAnswer(envelope, in: context)
        case Memory.syncTypeName: applyMemory(envelope, in: context)
        case CheckIn.syncTypeName: applyCheckIn(envelope, in: context)
        case MoonshotLevelResult.syncTypeName:
            applyProgress(envelope, in: context, localAuthorID: localAuthorID)
        // An unknown type is a newer build's record. Dropping it is right:
        // guessing at a payload we have no model for would corrupt the store,
        // and the record is still on the other phone when we catch up.
        default: false
        }
    }

    /// The shared decision, factored out so the four call sites can't drift.
    ///
    /// - `existing == nil`: take it, tombstone or not. **A tombstone for a
    ///   record we have never seen must still be stored**, otherwise an insert
    ///   arriving afterwards resurrects it — which is exactly what out-of-order
    ///   delivery does.
    /// - `existing` already tombstoned: never anything. **Tombstones are
    ///   sticky** (P21): a delete beats a concurrent edit whatever the
    ///   timestamps say. The cost is a lost edit; the alternative is a memory
    ///   you deliberately deleted reappearing days later.
    /// - Otherwise: last-writer-wins with the `authorID` tiebreak.
    static func verdict(for envelope: SyncEnvelope,
                        existingUpdatedAt: Date?,
                        existingAuthorID: String?,
                        existingDeletedAt: Date?) -> Bool {
        guard let existingUpdatedAt, let existingAuthorID else { return true }
        if existingDeletedAt != nil { return false }
        return envelope.supersedes(SyncEnvelope(recordType: envelope.recordType,
                                                id: envelope.id,
                                                authorID: existingAuthorID,
                                                updatedAt: existingUpdatedAt,
                                                deletedAt: nil,
                                                fields: [:]))
    }

    /// Mirrored (P20): the other phone's progress is stored so it can be
    /// *shown*, and this phone's own rows are never touched by a remote copy.
    ///
    /// The guard is the whole category. Without it, two installs that both
    /// think they are the same author merge campaign saves into each other —
    /// which is exactly what the old `"one"`-for-everyone key would have done.
    private static func applyProgress(_ envelope: SyncEnvelope,
                                      in context: ModelContext,
                                      localAuthorID: String) -> Bool {
        guard envelope.authorID != localAuthorID else { return false }

        let id = envelope.id
        let existing = try? context.fetch(
            FetchDescriptor<MoonshotLevelResult>(predicate: #Predicate { $0.id == id })).first
        // No tombstone case: progress is never deleted, only improved on.
        if let existing, existing.updatedAt >= envelope.updatedAt { return false }

        guard let levelID = envelope.string("levelID").flatMap(UUID.init(uuidString:)),
              let mode = envelope.string("modeRaw").flatMap(PlayMode.init(rawValue:))
        else { return false }

        let row = existing ?? {
            let created = MoonshotLevelResult(partnerID: envelope.authorID, levelID: levelID,
                                              mode: mode, cleared: false,
                                              bestStars: 0, bestFlings: 0)
            created.id = envelope.id
            context.insert(created)
            return created
        }()
        row.levelID = levelID
        row.modeRaw = mode.rawValue
        row.cleared = envelope.bool("cleared") ?? row.cleared
        row.bestStars = envelope.int("bestStars") ?? row.bestStars
        row.bestFlings = envelope.int("bestFlings") ?? row.bestFlings
        row.featOneFling = envelope.bool("featOneFling") ?? row.featOneFling
        row.featNoAbility = envelope.bool("featNoAbility") ?? row.featNoAbility
        row.featCleanSweep = envelope.bool("featCleanSweep") ?? row.featCleanSweep
        row.partnerID = envelope.authorID
        row.updatedAt = envelope.updatedAt
        return true
    }

    private static func applySpecialDate(_ envelope: SyncEnvelope,
                                         in context: ModelContext) -> Bool {
        let id = envelope.id
        let existing = try? context.fetch(
            FetchDescriptor<SpecialDate>(predicate: #Predicate { $0.id == id })).first
        guard verdict(for: envelope,
                      existingUpdatedAt: existing?.updatedAt,
                      existingAuthorID: existing?.authorID ?? "",
                      existingDeletedAt: existing?.deletedAt) else { return false }

        let row = existing ?? {
            let created = SpecialDate(title: "", date: .now)
            created.id = envelope.id
            context.insert(created)
            return created
        }()
        row.title = envelope.string("title") ?? row.title
        row.iconID = envelope.string("iconID") ?? row.iconID
        row.date = envelope.date("date") ?? row.date
        row.repeatsYearly = envelope.bool("repeatsYearly") ?? row.repeatsYearly
        row.isAnniversary = envelope.bool("isAnniversary") ?? row.isAnniversary
        row.authorID = envelope.authorID
        row.updatedAt = envelope.updatedAt
        row.deletedAt = envelope.deletedAt
        return true
    }

    private static func applyQuestionAnswer(_ envelope: SyncEnvelope,
                                            in context: ModelContext) -> Bool {
        let id = envelope.id
        let existing = try? context.fetch(
            FetchDescriptor<QuestionAnswer>(predicate: #Predicate { $0.id == id })).first
        guard verdict(for: envelope,
                      existingUpdatedAt: existing?.updatedAt,
                      existingAuthorID: existing?.authorID,
                      existingDeletedAt: existing?.deletedAt) else { return false }

        let row = existing ?? {
            let created = QuestionAnswer(questionID: "", day: .now, text: "", authorID: "")
            created.id = envelope.id
            context.insert(created)
            return created
        }()
        row.questionID = envelope.string("questionID") ?? row.questionID
        row.day = envelope.date("day") ?? row.day
        row.text = envelope.string("text") ?? row.text
        row.authorID = envelope.authorID
        row.updatedAt = envelope.updatedAt
        row.deletedAt = envelope.deletedAt
        return true
    }

    private static func applyMemory(_ envelope: SyncEnvelope,
                                    in context: ModelContext) -> Bool {
        let id = envelope.id
        let existing = try? context.fetch(
            FetchDescriptor<Memory>(predicate: #Predicate { $0.id == id })).first
        guard verdict(for: envelope,
                      existingUpdatedAt: existing?.updatedAt,
                      existingAuthorID: existing?.authorID,
                      existingDeletedAt: existing?.deletedAt) else { return false }

        let row = existing ?? {
            let created = Memory(note: "", day: nil, authorID: "", photoIDs: [])
            created.id = envelope.id
            context.insert(created)
            return created
        }()
        row.note = envelope.string("note") ?? row.note
        // Assigned unconditionally: absent means *undated* (H23), and treating
        // a missing key as "keep what we had" would make an edit that clears
        // the date impossible to replicate.
        row.day = envelope.date("day")
        row.photoIDs = envelope.strings("photoIDs") ?? row.photoIDs
        row.authorID = envelope.authorID
        row.updatedAt = envelope.updatedAt
        row.deletedAt = envelope.deletedAt
        return true
    }

    private static func applyCheckIn(_ envelope: SyncEnvelope,
                                     in context: ModelContext) -> Bool {
        let id = envelope.id
        let existing = try? context.fetch(
            FetchDescriptor<CheckIn>(predicate: #Predicate { $0.id == id })).first
        guard verdict(for: envelope,
                      existingUpdatedAt: existing?.updatedAt,
                      existingAuthorID: existing?.authorID,
                      existingDeletedAt: existing?.deletedAt) else { return false }

        let row = existing ?? {
            let created = CheckIn(day: .now, authorID: "")
            created.id = envelope.id
            context.insert(created)
            return created
        }()
        row.day = envelope.date("day") ?? row.day
        row.authorID = envelope.authorID
        row.updatedAt = envelope.updatedAt
        row.deletedAt = envelope.deletedAt
        return true
    }
}

extension SyncEnvelope {
    func string(_ key: String) -> String? {
        if case .string(let value)? = fields[key] { return value }
        return nil
    }

    func date(_ key: String) -> Date? {
        if case .date(let value)? = fields[key] { return value }
        return nil
    }

    func bool(_ key: String) -> Bool? {
        if case .bool(let value)? = fields[key] { return value }
        return nil
    }

    func int(_ key: String) -> Int? {
        if case .int(let value)? = fields[key] { return value }
        return nil
    }

    func strings(_ key: String) -> [String]? {
        if case .stringArray(let value)? = fields[key] { return value }
        return nil
    }
}
