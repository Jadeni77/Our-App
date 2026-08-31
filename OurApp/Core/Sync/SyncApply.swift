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
        case CoopLevelResult.syncTypeName: applyCoopLevelResult(envelope, in: context)
        case Profile.syncTypeName:
            applyProfile(envelope, in: context, localAuthorID: localAuthorID)
        case CoopMatch.syncTypeName: applyCoopMatch(envelope, in: context)
        case CoopTurn.syncTypeName: applyCoopTurn(envelope, in: context)
        case MoonshotLevelResult.syncTypeName:
            applyProgress(envelope, in: context, localAuthorID: localAuthorID)
        case Photo.syncTypeName: applyPhoto(envelope, in: context)
        case Album.syncTypeName: applyAlbum(envelope, in: context)
        case AlbumEntry.syncTypeName: applyAlbumEntry(envelope, in: context)
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

    /// **Merged, not overwritten.** Every other shared type takes the newer
    /// write; this one takes the *better* run. LWW here would let a two-star
    /// attempt clobber a three-star clear purely by being saved later, and the
    /// couple's record would go backwards.
    ///
    /// Max-merge is also strictly better behaved: commutative, associative and
    /// idempotent, so both phones converge in any delivery order with no
    /// tiebreak at all — unlike LWW, which needs `authorID` to converge (P21).
    private static func applyCoopLevelResult(_ envelope: SyncEnvelope,
                                             in context: ModelContext) -> Bool {
        let id = envelope.id
        let existing = try? context.fetch(
            FetchDescriptor<CoopLevelResult>(predicate: #Predicate { $0.id == id })).first
        // Sticky tombstone, as everywhere else (P21).
        if existing?.deletedAt != nil { return false }

        let incoming = CoopLedger.Snapshot(
            cleared: envelope.bool("cleared") ?? false,
            bestStars: envelope.int("bestStars") ?? 0,
            bestFlings: envelope.int("bestFlings") ?? 0,
            featOneFling: envelope.bool("featOneFling") ?? false,
            featNoAbility: envelope.bool("featNoAbility") ?? false,
            featCleanSweep: envelope.bool("featCleanSweep") ?? false)

        let row = existing ?? {
            let created = CoopLevelResult(levelID: envelope.id)
            context.insert(created)
            return created
        }()
        let merged = CoopLedger.merged(row.snapshot, incoming)
        guard merged != row.snapshot || existing == nil else { return false }
        row.apply(merged)
        row.updatedAt = max(row.updatedAt, envelope.updatedAt)
        row.deletedAt = envelope.deletedAt
        return true
    }

    /// **Never applied to your own row.**
    ///
    /// A mirrored record has exactly one rightful author, so an envelope
    /// claiming to be your profile is either your own write coming back — which
    /// is a no-op — or something that should not be honoured. Refusing it here
    /// means the phone you are holding is always the authority on you.
    private static func applyProfile(_ envelope: SyncEnvelope,
                                     in context: ModelContext,
                                     localAuthorID: String) -> Bool {
        // The guard is the whole category, exactly as it is for progress: this
        // phone is the authority on you, and a remote copy of your own row is
        // either your write coming back or something not to be honoured.
        guard envelope.authorID != localAuthorID else { return false }

        let id = envelope.id
        let existing = try? context.fetch(
            FetchDescriptor<Profile>(predicate: #Predicate { $0.id == id })).first
        guard verdict(for: envelope,
                      existingUpdatedAt: existing?.updatedAt,
                      existingAuthorID: existing?.authorID,
                      existingDeletedAt: existing?.deletedAt) else { return false }

        let row = existing ?? {
            let created = Profile(authorID: envelope.authorID)
            created.id = envelope.id
            context.insert(created)
            return created
        }()
        row.authorID = envelope.authorID
        row.name = envelope.string("name") ?? row.name
        row.pronoun = envelope.string("pronoun") ?? row.pronoun
        // Assigned unconditionally: clearing a photo is a thing somebody can
        // choose to do, and a picture that could not be removed would be worse
        // than one that arrives late.
        row.photoID = envelope.string("photoID")
        row.updatedAt = envelope.updatedAt
        row.deletedAt = envelope.deletedAt
        return true
    }

    private static func applyCoopMatch(_ envelope: SyncEnvelope,
                                       in context: ModelContext) -> Bool {
        let id = envelope.id
        let existing = try? context.fetch(
            FetchDescriptor<CoopMatch>(predicate: #Predicate { $0.id == id })).first

        // **A match advances on `turnIndex`, never on the clock.**
        //
        // LWW is wrong for this record, and wrong in a way that stalls the game
        // permanently. Both phones create a match for a level the moment it is
        // opened, and a match's id *is* its level's id, so the two creations
        // are two writes to one record. If she opens the level a minute after
        // you took your shot, her freshly-created match — turn 0, board
        // untouched — is the *newer* write, and LWW hands it the record. Your
        // turn is undone on both phones, she waits for a shot that already
        // happened, and nothing either of you does moves it: every reopen
        // rewrites turn 0 with a newer timestamp still.
        //
        // Observed exactly so on level 2: turn 1 at ...549.673 lost to turn 0
        // at ...553.426.
        //
        // Turn count only goes up, so taking the greater one is what the design
        // said (§3, "strictly increasing") and is a proper max-merge —
        // commutative, associative, idempotent, converging in any delivery
        // order. The clock only breaks ties at an equal index, which is the one
        // case where the two records really are the same moment in the game.
        let incomingIndex = envelope.int("turnIndex") ?? 0
        if let existing, envelope.deletedAt == nil {
            if incomingIndex < existing.turnIndex { return false }
            if incomingIndex == existing.turnIndex,
               !verdict(for: envelope,
                        existingUpdatedAt: existing.updatedAt,
                        existingAuthorID: existing.turnHolder,
                        existingDeletedAt: existing.deletedAt) { return false }
        } else {
            guard verdict(for: envelope,
                          existingUpdatedAt: existing?.updatedAt,
                          existingAuthorID: existing?.turnHolder,
                          existingDeletedAt: existing?.deletedAt) else { return false }
        }

        let row = existing ?? {
            let created = CoopMatch(levelID: UUID(), participants: [], turnHolder: "")
            created.id = envelope.id
            context.insert(created)
            return created
        }()
        row.levelID = envelope.string("levelID").flatMap(UUID.init(uuidString:)) ?? row.levelID
        row.participants = envelope.strings("participants") ?? row.participants
        row.turnHolder = envelope.string("turnHolder") ?? row.turnHolder
        row.turnIndex = envelope.int("turnIndex") ?? row.turnIndex
        row.boardState = envelope.string("boardState")
            .flatMap { Data(base64Encoded: $0) } ?? row.boardState
        // **Sticky, like a tombstone.** A cleared board is derived from bodies
        // that only ever die, so "we finished this" is monotonic and a record
        // arriving without it is stale news, not a retraction. Assigning it
        // unconditionally used to be defensible when the clock decided
        // everything; alongside index-max merge it would let a turn-0 record
        // un-win a level the two of you had already cleared.
        row.finishedAt = envelope.date("finishedAt") ?? row.finishedAt
        row.updatedAt = envelope.updatedAt
        row.deletedAt = envelope.deletedAt
        return true
    }

    /// Append-only: an existing turn is never rewritten, so a redelivery is a
    /// no-op rather than a merge.
    private static func applyCoopTurn(_ envelope: SyncEnvelope,
                                      in context: ModelContext) -> Bool {
        let id = envelope.id
        let existing = try? context.fetch(
            FetchDescriptor<CoopTurn>(predicate: #Predicate { $0.id == id })).first
        guard existing == nil else { return false }
        guard let matchID = envelope.string("matchID").flatMap(UUID.init(uuidString:)) else {
            return false
        }

        let created = CoopTurn(matchID: matchID,
                               index: envelope.int("index") ?? 0,
                               authorID: envelope.authorID,
                               clip: envelope.string("clip")
                                   .flatMap { Data(base64Encoded: $0) } ?? Data(),
                               resultingState: envelope.string("resultingState")
                                   .flatMap { Data(base64Encoded: $0) } ?? Data())
        created.id = envelope.id
        created.updatedAt = envelope.updatedAt
        created.deletedAt = envelope.deletedAt
        context.insert(created)
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
        if row.isAnniversary { collapseAnniversaries(in: context) }
        return true
    }

    /// Exactly one anniversary exists (P17), but each phone created its own row
    /// from its own legacy `couple.anniversary` key — so the first sync leaves
    /// two. Keep the **earlier** date, which is what the page and Home's day
    /// counter already pick, and tombstone the rest.
    ///
    /// Deterministic on purpose: both phones apply the same rule to the same
    /// set and reach the same answer without talking about it. Anything
    /// resolved by "whoever noticed first" would diverge.
    private static func collapseAnniversaries(in context: ModelContext) {
        let descriptor = FetchDescriptor<SpecialDate>(
            predicate: #Predicate { $0.deletedAt == nil && $0.isAnniversary })
        guard let rows = try? context.fetch(descriptor), rows.count > 1 else { return }

        let keeper = rows.min {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date
        }
        for row in rows where row.id != keeper?.id {
            row.deletedAt = .now
        }
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

    private static func applyPhoto(_ envelope: SyncEnvelope,
                                   in context: ModelContext) -> Bool {
        let id = envelope.id
        let existing = try? context.fetch(
            FetchDescriptor<Photo>(predicate: #Predicate { $0.id == id })).first
        guard verdict(for: envelope,
                      existingUpdatedAt: existing?.updatedAt,
                      existingAuthorID: existing?.authorID,
                      existingDeletedAt: existing?.deletedAt) else { return false }

        let row = existing ?? {
            let created = Photo(assetID: envelope.string("assetID") ?? "",
                                authorID: envelope.authorID)
            created.id = envelope.id
            context.insert(created)
            return created
        }()
        row.assetID = envelope.string("assetID") ?? row.assetID
        row.authorID = envelope.authorID
        row.caption = envelope.string("caption") ?? row.caption
        row.addedAt = envelope.date("addedAt") ?? row.addedAt
        // Assigned unconditionally: clearing a date is a thing somebody can do.
        row.takenAt = envelope.date("takenAt")
        row.updatedAt = envelope.updatedAt
        row.deletedAt = envelope.deletedAt
        return true
    }

    private static func applyAlbum(_ envelope: SyncEnvelope,
                                   in context: ModelContext) -> Bool {
        let id = envelope.id
        let existing = try? context.fetch(
            FetchDescriptor<Album>(predicate: #Predicate { $0.id == id })).first
        guard verdict(for: envelope,
                      existingUpdatedAt: existing?.updatedAt,
                      existingAuthorID: existing?.authorID,
                      existingDeletedAt: existing?.deletedAt) else { return false }

        let row = existing ?? {
            let created = Album(name: "", authorID: envelope.authorID)
            created.id = envelope.id
            context.insert(created)
            return created
        }()
        row.name = envelope.string("name") ?? row.name
        row.authorID = envelope.authorID
        row.createdAt = envelope.date("createdAt") ?? row.createdAt
        // Unconditional: removing a chosen cover falls back to the newest
        // member, which is a choice somebody may make deliberately.
        row.coverAssetID = envelope.string("coverAssetID")
        row.updatedAt = envelope.updatedAt
        row.deletedAt = envelope.deletedAt
        return true
    }

    /// Append-and-tombstone: a membership is only ever added or removed, never
    /// edited, so there is nothing here to conflict over beyond which of those
    /// happened last.
    private static func applyAlbumEntry(_ envelope: SyncEnvelope,
                                        in context: ModelContext) -> Bool {
        let id = envelope.id
        let existing = try? context.fetch(
            FetchDescriptor<AlbumEntry>(predicate: #Predicate { $0.id == id })).first
        guard verdict(for: envelope,
                      existingUpdatedAt: existing?.updatedAt,
                      existingAuthorID: existing?.authorID,
                      existingDeletedAt: existing?.deletedAt) else { return false }

        guard let albumID = envelope.string("albumID").flatMap(UUID.init(uuidString:)),
              let assetID = envelope.string("assetID")
        else { return false }

        let row = existing ?? {
            let created = AlbumEntry(albumID: albumID, assetID: assetID,
                                     authorID: envelope.authorID)
            created.id = envelope.id
            context.insert(created)
            return created
        }()
        row.albumID = albumID
        row.assetID = assetID
        row.authorID = envelope.authorID
        row.addedAt = envelope.date("addedAt") ?? row.addedAt
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
