import Foundation
import SwiftData
import Testing
import UIKit
@testable import OurApp

/// Two phones, one process. `LoopbackCloud` stands in for the network, so every
/// merge rule below is proven with no entitlement and no paid Apple account —
/// which is the whole point of slice A.
@MainActor
struct SyncConvergenceTests {
    private struct Phone {
        let context: ModelContext
        let engine: SyncEngine
        let authorID: String
    }

    private func pair() throws -> (Phone, Phone) {
        let cloud = LoopbackCloud()
        func phone(_ authorID: String) throws -> Phone {
            let context = ModelContext(try Persistence.makeContainer(inMemory: true))
            let suite = "sync.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            return Phone(context: context,
                         engine: SyncEngine(context: context,
                                            transport: LoopbackTransport(cloud: cloud),
                                            authorID: authorID,
                                            defaults: defaults),
                         authorID: authorID)
        }
        // "a" < "b" lexicographically, which is what the tiebreak turns on.
        return (try phone("author-a"), try phone("author-b"))
    }

    private func memories(_ phone: Phone) throws -> [Memory] {
        try phone.context.fetch(FetchDescriptor<Memory>(predicate: Memory.visible))
    }

    @Test func aRecordWrittenOnOnePhoneArrivesOnTheOther() async throws {
        let (a, b) = try pair()
        a.context.insert(Memory(note: "Kyoto", day: .now,
                                authorID: a.authorID, photoIDs: ["p1"]))
        try a.context.save()

        try await a.engine.tick()
        try await b.engine.tick()

        let arrived = try memories(b)
        #expect(arrived.count == 1)
        #expect(arrived.first?.note == "Kyoto")
        #expect(arrived.first?.photoIDs == ["p1"])
    }

    @Test func anUndatedMemoryStaysUndatedAcross() async throws {
        let (a, b) = try pair()
        a.context.insert(Memory(note: "no idea when", day: nil,
                                authorID: a.authorID, photoIDs: ["p1"]))
        try a.context.save()

        try await a.engine.tick()
        try await b.engine.tick()

        // Absent must survive as absent (H23) — a sentinel date here would put
        // a wrong day on the other phone and look authoritative.
        #expect(try memories(b).first?.day == nil)
    }

    @Test func aTombstoneRemovesTheRowOnTheOtherPhone() async throws {
        let (a, b) = try pair()
        let memory = Memory(note: "gone", day: .now,
                            authorID: a.authorID, photoIDs: ["p1"])
        a.context.insert(memory)
        try a.context.save()
        try await a.engine.tick()
        try await b.engine.tick()
        #expect(try memories(b).count == 1)

        memory.deletedAt = .now
        memory.updatedAt = .now
        try a.context.save()
        try await a.engine.tick()
        try await b.engine.tick()

        #expect(try memories(b).isEmpty)
    }

    @Test func aDeleteArrivingBeforeTheInsertDoesNotResurrect() async throws {
        let (a, b) = try pair()
        let id = UUID()
        let created = Date(timeIntervalSinceReferenceDate: 800_000_000)

        func envelope(deleted: Date?, updatedAt: Date) -> SyncEnvelope {
            SyncEnvelope(recordType: Memory.syncTypeName, id: id,
                         authorID: a.authorID, updatedAt: updatedAt,
                         deletedAt: deleted,
                         fields: ["note": .string("gone"),
                                  "photoIDs": .stringArray(["p1"])])
        }

        // Out of order on purpose: the delete lands first, for a record this
        // phone has never seen. Storing the tombstone anyway is what stops the
        // insert behind it from resurrecting the row.
        SyncApply.apply(envelope(deleted: created.addingTimeInterval(60),
                                 updatedAt: created.addingTimeInterval(60)),
                        in: b.context, localAuthorID: b.authorID)
        SyncApply.apply(envelope(deleted: nil, updatedAt: created),
                        in: b.context, localAuthorID: b.authorID)
        try b.context.save()

        #expect(try memories(b).isEmpty)
    }

    @Test func aTombstoneBeatsANewerEdit() async throws {
        let (a, b) = try pair()
        let id = UUID()
        let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

        SyncApply.apply(SyncEnvelope(recordType: Memory.syncTypeName, id: id,
                                     authorID: a.authorID, updatedAt: base,
                                     deletedAt: base,
                                     fields: ["note": .string("deleted")]),
                        in: b.context, localAuthorID: b.authorID)
        // Strictly newer, and still ignored: tombstones are sticky (P21). The
        // edit is lost, which beats a deliberately deleted memory reappearing.
        SyncApply.apply(SyncEnvelope(recordType: Memory.syncTypeName, id: id,
                                     authorID: b.authorID,
                                     updatedAt: base.addingTimeInterval(3600),
                                     deletedAt: nil,
                                     fields: ["note": .string("edited later")]),
                        in: b.context, localAuthorID: b.authorID)
        try b.context.save()

        #expect(try memories(b).isEmpty)
    }

    @Test func simultaneousEditsConvergeOnTheSameValueOnBothPhones() async throws {
        let (a, b) = try pair()
        let id = UUID()
        let sameInstant = Date(timeIntervalSinceReferenceDate: 800_000_000)

        func edit(by author: String, note: String) -> SyncEnvelope {
            SyncEnvelope(recordType: Memory.syncTypeName, id: id,
                         authorID: author, updatedAt: sameInstant, deletedAt: nil,
                         fields: ["note": .string(note), "photoIDs": .stringArray([])])
        }

        // Same timestamp, different authors, and delivered in opposite orders.
        // Without the authorID tiebreak each phone keeps its own and they
        // disagree forever, with no conflict anybody could ever see.
        for envelope in [edit(by: "author-a", note: "hers"), edit(by: "author-b", note: "his")] {
            SyncApply.apply(envelope, in: a.context, localAuthorID: a.authorID)
        }
        for envelope in [edit(by: "author-b", note: "his"), edit(by: "author-a", note: "hers")] {
            SyncApply.apply(envelope, in: b.context, localAuthorID: b.authorID)
        }
        try a.context.save()
        try b.context.save()

        let left = try memories(a).first?.note
        let right = try memories(b).first?.note
        #expect(left == right)
        #expect(left == "his")     // "author-b" > "author-a"
    }

    @Test func applyingTheSameEnvelopeTwiceChangesNothing() async throws {
        let (a, b) = try pair()
        let envelope = SyncEnvelope(recordType: CheckIn.syncTypeName, id: UUID(),
                                    authorID: a.authorID, updatedAt: .now, deletedAt: nil,
                                    fields: ["day": .date(.now)])
        SyncApply.apply(envelope, in: b.context, localAuthorID: b.authorID)
        let second = SyncApply.apply(envelope, in: b.context, localAuthorID: b.authorID)
        try b.context.save()

        #expect(second == false)
        #expect(try b.context.fetchCount(FetchDescriptor<CheckIn>()) == 1)
    }

    @Test func aPartnersCheckInIsCountedAlongsideYoursRatherThanMerged() async throws {
        let (a, b) = try pair()
        let day = Date(timeIntervalSinceReferenceDate: 800_000_000)
        CheckInStore.checkIn(in: a.context, authorID: a.authorID, on: day)
        CheckInStore.checkIn(in: b.context, authorID: b.authorID, on: day)

        try await a.engine.tick()
        try await b.engine.tick()
        try await a.engine.tick()

        // Two rows for one day, one per author — this is what makes the 火花
        // mutual when slice D lands, and why check-ins never conflict.
        let all = try a.context.fetch(FetchDescriptor<CheckIn>())
        #expect(all.count == 2)
        #expect(CheckInStore.days(in: a.context, authorID: a.authorID).count == 1)
    }

    @Test func anEchoOfYourOwnRecordDoesNotOverwriteALocalEdit() async throws {
        let (a, _) = try pair()
        let memory = Memory(note: "first", day: .now, authorID: a.authorID, photoIDs: [])
        a.context.insert(memory)
        try a.context.save()
        let echo = memory.envelope()          // captured *before* the local edit

        memory.note = "edited after pushing"
        memory.updatedAt = memory.updatedAt.addingTimeInterval(60)
        try a.context.save()

        // Applied directly. Driving this through `tick()` proved nothing: the
        // first tick advanced the pull cursor past the original envelope, so
        // the stale echo the test is named for never arrived and the assertion
        // held even with the merge rule removed entirely.
        let applied = SyncApply.apply(echo, in: a.context, localAuthorID: a.authorID)
        try a.context.save()

        #expect(applied == false)
        #expect(try memories(a).first?.note == "edited after pushing")
    }

    @Test func aLocalWriteIsPushedEvenWhenThePartnersClockRunsAhead() async throws {
        let (a, b) = try pair()
        // The watermark used to be max(updatedAt) over *everything* collected,
        // including rows that arrived from the other phone carrying its clock.
        // A partner ten minutes fast pushed this phone's watermark into its own
        // future, and every local write below it was never pushed at all.
        let fromThem = Memory(note: "theirs, from the future", day: .now,
                              authorID: b.authorID, photoIDs: [])
        fromThem.updatedAt = Date().addingTimeInterval(600)
        a.context.insert(fromThem)
        try a.context.save()
        try await a.engine.tick()

        a.context.insert(Memory(note: "mine, written now", day: .now,
                                authorID: a.authorID, photoIDs: []))
        try a.context.save()
        try await a.engine.tick()
        try await b.engine.tick()

        #expect(try memories(b).contains { $0.note == "mine, written now" })
    }

    @Test func anUnknownRecordTypeIsDroppedRatherThanGuessedAt() async throws {
        let (_, b) = try pair()
        let applied = SyncApply.apply(
            SyncEnvelope(recordType: "SomethingFromANewerBuild", id: UUID(),
                         authorID: "x", updatedAt: .now, deletedAt: nil, fields: [:]),
            in: b.context, localAuthorID: b.authorID)
        #expect(applied == false)
    }
}

@MainActor
struct FileCloudTransportTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func envelope(_ note: String, author: String = "author-a") -> SyncEnvelope {
        SyncEnvelope(recordType: Memory.syncTypeName, id: UUID(),
                     authorID: author, updatedAt: .now, deletedAt: nil,
                     fields: ["note": .string(note)])
    }

    /// Two transports on one folder — which is the whole point, and what the
    /// first version of these tests never did: they used a single instance and
    /// always pulled after their own push, so a two-writer directory was never
    /// exercised at all.
    private func pair() throws -> (FileCloudTransport, FileCloudTransport) {
        let folder = try directory()
        return (FileCloudTransport(directory: folder, authorID: "author-a"),
                FileCloudTransport(directory: folder, authorID: "author-b"))
    }

    @Test func envelopesRoundTripThroughARealDirectory() async throws {
        let (a, b) = try pair()
        let sent = envelope("Kyoto")
        try await a.push([sent])

        #expect(try await b.pull(since: nil).envelopes == [sent])
    }

    @Test func yourOwnWritesAreNotPulledBack() async throws {
        let (a, _) = try pair()
        try await a.push([envelope("mine")])

        // They used to be, and pulling them was what dragged the cursor past
        // the other phone's files.
        #expect(try await a.pull(since: nil).envelopes.isEmpty)
    }

    @Test func aWriterWithASlowerClockIsStillDelivered() async throws {
        let (a, b) = try pair()
        // The bug this replaces: filenames were stamped with the writer's wall
        // clock and the cursor was a single high-water string. A pushes (and so
        // sets its own cursor high), B pushes with a clock a few minutes behind,
        // and B's file sorts *below* A's cursor — skipped forever, silently.
        // Sequences are per writer, so no clock can order one writer's records
        // relative to another's.
        try await a.push([envelope("from a", author: "author-a")])
        let first = try await a.pull(since: nil)
        try await b.push([envelope("from b", author: "author-b")])

        let second = try await a.pull(since: first.token)
        #expect(second.envelopes.map { $0.string("note") } == ["from b"])
    }

    @Test func pullingAgainWithTheCursorReturnsNothing() async throws {
        let (a, b) = try pair()
        try await a.push([envelope("one")])
        let first = try await b.pull(since: nil)

        let second = try await b.pull(since: first.token)
        // An idle tick must not re-deliver: without this the other phone
        // re-applies the same envelopes on every foreground, forever.
        #expect(second.envelopes.isEmpty)
    }

    @Test func onlyEnvelopesAfterTheCursorComeBack() async throws {
        let (a, b) = try pair()
        try await a.push([envelope("one")])
        let first = try await b.pull(since: nil)
        try await a.push([envelope("two")])

        let second = try await b.pull(since: first.token)
        #expect(second.envelopes.count == 1)
        #expect(second.envelopes.first?.string("note") == "two")
    }

    @Test func aHalfWrittenOrForeignFileIsSkippedRatherThanFatal() async throws {
        let (a, b) = try pair()
        try await a.push([envelope("good")])
        try Data("not json".utf8)
            .write(to: a.directory.appendingPathComponent("author-a__0000009999__x.json"))

        // Principle 7 at the transport layer: one unreadable file must not stop
        // every other record from arriving.
        let batch = try await b.pull(since: nil)
        #expect(batch.envelopes.count == 1)
        #expect(batch.envelopes.first?.string("note") == "good")
    }

    @Test func onePushersRecordsArriveInOrderAcrossSeparatePushes() async throws {
        let (a, b) = try pair()
        for index in 0..<12 {
            try await a.push([envelope("note-\(index)")])
        }
        // Sequence continues across pushes — it is recovered from the directory
        // rather than held in memory, so a relaunched app doesn't restart at 1
        // and overwrite its own history.
        #expect(try await b.pull(since: nil).envelopes.map { $0.string("note") }
                == (0..<12).map { "note-\($0)" })
    }

    @Test func twoWritersInterleaveWithoutHidingEachOther() async throws {
        let (a, b) = try pair()
        try await a.push([envelope("a1", author: "author-a")])
        try await b.push([envelope("b1", author: "author-b")])
        try await a.push([envelope("a2", author: "author-a")])

        let seen = try await FileCloudTransport(directory: a.directory, authorID: "reader")
            .pull(since: nil).envelopes.map { $0.string("note") }
        #expect(Set(seen) == ["a1", "a2", "b1"])
    }
}

/// Counts calls, so "it didn't ask" can be asserted rather than inferred from
/// a nil that several different bugs also produce.
actor CountingAssetTransport: SyncAssetTransport {
    private(set) var puts = 0
    private(set) var gets = 0
    private var stored: [String: Data] = [:]

    func putAsset(_ data: Data, id: String) async throws {
        puts += 1
        stored[id] = data
    }

    func getAsset(id: String) async throws -> Data? {
        gets += 1
        return stored[id]
    }

    func hasAsset(id: String) async -> Bool { stored[id] != nil }

    func forget(_ id: String) { stored[id] = nil }
}

@MainActor
struct SyncAssetTests {
    private func photoStore() throws -> MemoryPhotoStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return MemoryPhotoStore(directory: url)
    }

    private func jpeg() -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 900, height: 600), format: format)
            .image { context in
                UIColor.systemPink.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 900, height: 600))
            }.jpegData(compressionQuality: 0.9)!
    }

    private func context() throws -> ModelContext {
        ModelContext(try Persistence.makeContainer(inMemory: true))
    }

    @Test func anAssetLostFromTheCloudIsUploadedAgain() async throws {
        let spy = CountingAssetTransport()
        let store = try photoStore()
        let id = try store.write(jpeg(), id: UUID().uuidString)
        let sending = try context()
        sending.insert(Memory(note: "once", day: .now, authorID: "author-a", photoIDs: [id]))
        try sending.save()

        await SyncAssetPump.upload(context: sending, transport: spy, photos: store)
        await spy.forget(id)          // the folder moved, or the asset went
        await SyncAssetPump.upload(context: sending, transport: spy, photos: store)

        // With a remembered list this never happened again, and the partner's
        // grid kept its placeholders forever while download retried an id
        // nobody would ever supply.
        #expect(await spy.puts == 2)
    }

    private func defaults() -> UserDefaults {
        let suite = "assets.test.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        store.removePersistentDomain(forName: suite)
        return store
    }

    @Test func aPhotoUploadedByOnePhoneIsWrittenOnTheOther() async throws {
        let cloud = LoopbackCloud()
        let transport = LoopbackTransport(cloud: cloud)
        let sender = try photoStore()
        let receiver = try photoStore()
        let id = try sender.write(jpeg(), id: UUID().uuidString)

        let sending = try context()
        sending.insert(Memory(note: "with a picture", day: .now,
                              authorID: "author-a", photoIDs: [id]))
        try sending.save()
        await SyncAssetPump.upload(context: sending, transport: transport, photos: sender)

        let receiving = try context()
        receiving.insert(Memory(note: "with a picture", day: .now,
                                authorID: "author-a", photoIDs: [id]))
        try receiving.save()
        let arrived = await SyncAssetPump.download(context: receiving,
                                                   transport: transport, photos: receiver)

        #expect(arrived == [id])
        #expect(receiver.has(id))
        // The thumbnail is regenerated locally rather than transferred, so it
        // is guaranteed to be derived from the image it sits under.
        #expect(receiver.thumbnail(for: id) != nil)
    }

    @Test func aPhotoNotYetUploadedIsSimplyRetriedNextTick() async throws {
        let transport = LoopbackTransport(cloud: LoopbackCloud())
        let receiver = try photoStore()
        let id = UUID().uuidString

        let receiving = try context()
        receiving.insert(Memory(note: "picture still coming", day: .now,
                                authorID: "author-a", photoIDs: [id]))
        try receiving.save()

        // Records outrun their pictures by design: nothing is uploaded yet, so
        // this is a normal state and not a failure.
        let first = await SyncAssetPump.download(context: receiving,
                                                 transport: transport, photos: receiver)
        #expect(first.isEmpty)
        #expect(!receiver.has(id))

        let sender = try photoStore()
        try sender.write(jpeg(), id: id)
        try await transport.putAsset(sender.storedData(for: id)!, id: id)

        let second = await SyncAssetPump.download(context: receiving,
                                                  transport: transport, photos: receiver)
        #expect(second == [id])
    }

    @Test func aPhotoAlreadyOnDiskIsNotFetchedAgain() async throws {
        let spy = CountingAssetTransport()
        let store = try photoStore()
        let id = try store.write(jpeg(), id: UUID().uuidString)

        let receiving = try context()
        receiving.insert(Memory(note: "already here", day: .now,
                                authorID: "author-a", photoIDs: [id]))
        try receiving.save()

        _ = await SyncAssetPump.download(context: receiving, transport: spy, photos: store)

        // Counted, not inferred. Asserting only that `download` returned empty
        // proved nothing: an id nobody uploaded also yields nil and an empty
        // result, so the guard being absent looked identical.
        #expect(await spy.gets == 0)
    }

    @Test func uploadingIsNotRepeatedOnEveryTick() async throws {
        let spy = CountingAssetTransport()
        let store = try photoStore()
        let shared = defaults()
        let id = try store.write(jpeg(), id: UUID().uuidString)

        let sending = try context()
        sending.insert(Memory(note: "once", day: .now, authorID: "author-a", photoIDs: [id]))
        try sending.save()

        for _ in 0..<3 {
            await SyncAssetPump.upload(context: sending, transport: spy, photos: store)
        }

        // Counted. The old version deleted the local file between ticks and
        // then checked the asset existed — which it did, from the *first*
        // upload, whether or not the latch worked at all.
        #expect(await spy.puts == 1)
    }

    @Test func aThumbnailCacheForgetsAMissSoAnArrivingPhotoShows() async throws {
        let store = try photoStore()
        let cache = MemoryThumbnails(store: store)
        let id = UUID().uuidString

        await cache.loadIfNeeded(id)
        #expect(cache.image(for: id) == nil)

        try store.write(jpeg(), id: id)
        // Without `forget`, the remembered miss keeps the placeholder on screen
        // until relaunch — indistinguishable from sync having failed.
        cache.forget(id)
        await cache.loadIfNeeded(id)
        #expect(cache.image(for: id) != nil)
    }
}

@MainActor
struct MirroredProgressTests {
    private func context() throws -> ModelContext {
        ModelContext(try Persistence.makeContainer(inMemory: true))
    }

    private func envelope(author: String, levelID: UUID, stars: Int,
                          updatedAt: Date = .now, id: UUID = UUID()) -> SyncEnvelope {
        SyncEnvelope(recordType: MoonshotLevelResult.syncTypeName, id: id,
                     authorID: author, updatedAt: updatedAt, deletedAt: nil,
                     fields: ["levelID": .string(levelID.uuidString),
                              "modeRaw": .string(PlayMode.solo.rawValue),
                              "cleared": .bool(true),
                              "bestStars": .int(stars),
                              "bestFlings": .int(3),
                              "featOneFling": .bool(false),
                              "featNoAbility": .bool(false),
                              "featCleanSweep": .bool(false)])
    }

    @Test func thePartnersProgressIsStoredSeparatelyFromYours() throws {
        let store = try context()
        let level = UUID()
        MoonshotProgressStore(context: store, partnerID: "me")
            .recordSolo(levelID: level, cleared: true, stars: 1, flings: 9)

        SyncApply.apply(envelope(author: "them", levelID: level, stars: 3),
                        in: store, localAuthorID: "me")
        try store.save()

        // Two rows for one level: yours and theirs. Campaign progress is
        // mirrored, never merged — the owner's rule.
        let all = try store.fetch(FetchDescriptor<MoonshotLevelResult>())
        #expect(all.count == 2)
        #expect(all.first { $0.partnerID == "me" }?.bestStars == 1)
        #expect(all.first { $0.partnerID == "them" }?.bestStars == 3)
    }

    @Test func anEnvelopeClaimingToBeYouIsIgnored() throws {
        let store = try context()
        let level = UUID()
        MoonshotProgressStore(context: store, partnerID: "me")
            .recordSolo(levelID: level, cleared: true, stars: 1, flings: 9)

        // The failure this guards: two installs that both believe they are the
        // same author would merge campaign saves into each other, which is what
        // the old "one"-for-every-phone key set up.
        let applied = SyncApply.apply(envelope(author: "me", levelID: level, stars: 3),
                                      in: store, localAuthorID: "me")
        try store.save()

        #expect(applied == false)
        #expect(try store.fetch(FetchDescriptor<MoonshotLevelResult>()).count == 1)
        #expect(try store.fetch(FetchDescriptor<MoonshotLevelResult>()).first?.bestStars == 1)
    }

    @Test func anOlderCopyOfTheirProgressDoesNotUndoANewerOne() throws {
        let store = try context()
        let level = UUID()
        let rowID = UUID()
        let newer = Date(timeIntervalSinceReferenceDate: 800_000_000)

        SyncApply.apply(envelope(author: "them", levelID: level, stars: 3,
                                 updatedAt: newer, id: rowID),
                        in: store, localAuthorID: "me")
        SyncApply.apply(envelope(author: "them", levelID: level, stars: 1,
                                 updatedAt: newer.addingTimeInterval(-3600), id: rowID),
                        in: store, localAuthorID: "me")
        try store.save()

        #expect(try store.fetch(FetchDescriptor<MoonshotLevelResult>()).first?.bestStars == 3)
    }

    @Test func legacyProgressKeyedToOneBecomesThisInstalls() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let store = ModelContext(container)
        MoonshotProgressStore(context: store, partnerID: Partner.one.rawValue)
            .recordSolo(levelID: UUID(), cleared: true, stars: 2, flings: 5)
        try store.save()

        AuthorIDMigration.runIfNeeded(in: container, authorID: "this-install")

        let migrated = try ModelContext(container)
            .fetch(FetchDescriptor<MoonshotLevelResult>()).first
        // Every phone wrote "one", because the defaults key it read was never
        // written by anything. Left alone, both phones' progress collides the
        // moment sync starts.
        #expect(migrated?.partnerID == "this-install")
    }
}

@MainActor
struct ProgressScopingTests {
    private func context() throws -> ModelContext {
        ModelContext(try Persistence.makeContainer(inMemory: true))
    }

    @Test func mineExcludesThePartnersRowsAndTheirsIsTheComplement() throws {
        let store = try context()
        let mine = LocalAuthor.id()
        MoonshotProgressStore(context: store, partnerID: mine)
            .recordSolo(levelID: UUID(), cleared: true, stars: 3, flings: 2)
        MoonshotProgressStore(context: store, partnerID: "them")
            .recordSolo(levelID: UUID(), cleared: true, stars: 2, flings: 4)
        try store.save()

        let all = try store.fetch(FetchDescriptor<MoonshotLevelResult>())
        #expect(all.count == 2)
        #expect(all.mine.count == 1)
        #expect(all.theirs.count == 1)
        #expect(all.mine.first?.bestStars == 3)
    }

    @Test func thePooledStarCountDeliberatelyCountsBoth() throws {
        let store = try context()
        MoonshotProgressStore(context: store, partnerID: LocalAuthor.id())
            .recordSolo(levelID: UUID(), cleared: true, stars: 3, flings: 2)
        MoonshotProgressStore(context: store, partnerID: "them")
            .recordSolo(levelID: UUID(), cleared: true, stars: 2, flings: 4)
        try store.save()

        // "Every star either of us earns lights this up" — the promise on the
        // Moonshot home screen. Clear state is personal; the sky is not, and
        // scoping this one would quietly break a stated design.
        let all = try store.fetch(FetchDescriptor<MoonshotLevelResult>())
        #expect(MoonshotRewards.starPool(all.map(\.snapshot)) == 5)
        #expect(MoonshotRewards.starPool(all.mine.map(\.snapshot)) == 3)
    }
}

@MainActor
struct CoupleWalletTests {
    @Test func moondustSumsBothPartnersBecauseItIsOneWallet() throws {
        let store = ModelContext(try Persistence.makeContainer(inMemory: true))
        MoonshotProgressStore(context: store, partnerID: LocalAuthor.id())
            .addMoondust(30, reason: "smash")
        MoonshotProgressStore(context: store, partnerID: "them")
            .addMoondust(20, reason: "smash")
        try store.save()

        // M31: "over ALL partners' rows (one couple wallet)". Scoping this the
        // way clear state is scoped would silently halve the balance the first
        // time sync ran — the same mistake as scoping the star pool, made twice.
        let all = try store.fetch(FetchDescriptor<MoonshotMoondustEntry>())
        #expect(all.reduce(0) { $0 + $1.amount } == 50)
    }
}

@MainActor
struct SharedRecordAuthorshipTests {
    /// Every shared type must carry a real author, because the LWW tiebreak
    /// breaks on it. A type that ships `""` has no tiebreak at all.
    @Test func everySharedRecordIsCreatedWithAnAuthor() throws {
        let store = ModelContext(try Persistence.makeContainer(inMemory: true))
        let mine = LocalAuthor.id()

        store.insert(SpecialDate(title: "First date", date: .now))
        store.insert(Memory(note: "", day: .now, authorID: mine, photoIDs: ["a"]))
        store.insert(CheckIn(day: .now, authorID: mine))
        DailyQuestionStore.write("x", in: store, questionID: "q01", day: .now, authorID: mine)
        try store.save()

        #expect(try store.fetch(FetchDescriptor<SpecialDate>()).first?.authorID == mine)
        #expect(try store.fetch(FetchDescriptor<Memory>()).first?.authorID == mine)
        #expect(try store.fetch(FetchDescriptor<CheckIn>()).first?.authorID == mine)
        #expect(try store.fetch(FetchDescriptor<QuestionAnswer>()).first?.authorID == mine)
    }

    @Test func twoPhonesEditingOneDateAtTheSameInstantStillConverge() throws {
        func apply(_ order: [SyncEnvelope]) throws -> String? {
            let store = ModelContext(try Persistence.makeContainer(inMemory: true))
            for envelope in order {
                SyncApply.apply(envelope, in: store, localAuthorID: "reader")
            }
            try store.save()
            return try store.fetch(FetchDescriptor<SpecialDate>()).first?.title
        }
        let id = UUID()
        let instant = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func edit(_ author: String, _ title: String) -> SyncEnvelope {
            SyncEnvelope(recordType: SpecialDate.syncTypeName, id: id, authorID: author,
                         updatedAt: instant, deletedAt: nil,
                         fields: ["title": .string(title), "iconID": .string("heart"),
                                  "date": .date(instant), "repeatsYearly": .bool(false),
                                  "isAnniversary": .bool(false)])
        }
        let forward = try apply([edit("author-a", "hers"), edit("author-b", "his")])
        let backward = try apply([edit("author-b", "his"), edit("author-a", "hers")])

        #expect(forward == backward)
        #expect(forward == "his")
    }
}

@MainActor
struct AnniversaryConvergenceTests {
    private func anniversary(_ date: Date, author: String, id: UUID = UUID()) -> SyncEnvelope {
        SyncEnvelope(recordType: SpecialDate.syncTypeName, id: id, authorID: author,
                     updatedAt: .now, deletedAt: nil,
                     fields: ["title": .string(""), "iconID": .string("heart"),
                              "date": .date(date), "repeatsYearly": .bool(true),
                              "isAnniversary": .bool(true)])
    }

    @Test func twoPhonesEachMigratingTheirOwnAnniversaryEndUpWithOne() throws {
        let store = ModelContext(try Persistence.makeContainer(inMemory: true))
        let earlier = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let later = Date(timeIntervalSinceReferenceDate: 800_000_000)

        // Each phone made its own row from its own legacy defaults key, so both
        // exist after the first sync — and the day counter would silently
        // change on whichever phone held the later one.
        let mine = SpecialDate(title: "", date: later, repeatsYearly: true, isAnniversary: true)
        store.insert(mine)
        SyncApply.apply(anniversary(earlier, author: "them"), in: store, localAuthorID: "me")
        try store.save()

        let live = try store.fetch(
            FetchDescriptor<SpecialDate>(predicate: #Predicate { $0.deletedAt == nil }))
        #expect(live.count == 1)
        #expect(live.first?.date == earlier)
    }

    @Test func bothPhonesCollapseToTheSameAnniversary() throws {
        let earlier = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let later = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let mineID = UUID(), theirsID = UUID()

        func survivor(localDate: Date, localID: UUID,
                      incoming: SyncEnvelope) throws -> Date? {
            let store = ModelContext(try Persistence.makeContainer(inMemory: true))
            let row = SpecialDate(title: "", date: localDate,
                                  repeatsYearly: true, isAnniversary: true)
            row.id = localID
            store.insert(row)
            SyncApply.apply(incoming, in: store, localAuthorID: "me")
            try store.save()
            return try store.fetch(FetchDescriptor<SpecialDate>(
                predicate: #Predicate { $0.deletedAt == nil })).first?.date
        }

        // Same rule, opposite starting points: the phones must agree without
        // negotiating. "Whoever noticed first wins" would leave them different.
        let onMine = try survivor(localDate: later, localID: mineID,
                                  incoming: anniversary(earlier, author: "them", id: theirsID))
        let onTheirs = try survivor(localDate: earlier, localID: theirsID,
                                    incoming: anniversary(later, author: "me", id: mineID))
        #expect(onMine == onTheirs)
        #expect(onMine == earlier)
    }
}

@MainActor
struct SyncOutboxTests {
    private func outbox(_ author: String = "me") throws -> SyncOutbox {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return SyncOutbox(directory: url, authorID: author)
    }

    private func envelope(_ note: String) -> SyncEnvelope {
        SyncEnvelope(recordType: Memory.syncTypeName, id: UUID(), authorID: "me",
                     updatedAt: .now, deletedAt: nil, fields: ["note": .string(note)])
    }

    @Test func entriesComeBackInSequenceOrder() throws {
        let log = try outbox()
        try log.append((0..<12).map { envelope("note-\($0)") })

        #expect(log.entries(after: 0).map { $0.envelope.string("note") }
                == (0..<12).map { "note-\($0)" })
    }

    @Test func sequenceContinuesAcrossSeparateAppends() throws {
        let log = try outbox()
        try log.append([envelope("one")])
        try log.append([envelope("two")])

        // Recovered from disk rather than held in memory: a relaunched app that
        // restarted at 1 would overwrite its own history and a peer would never
        // see the second half of it.
        #expect(log.highestSequence() == 2)
        #expect(SyncOutbox(directory: log.directory, authorID: "me").highestSequence() == 2)
    }

    @Test func onlyEntriesAfterTheCursorAreServed() throws {
        let log = try outbox()
        try log.append([envelope("one"), envelope("two"), envelope("three")])

        #expect(log.entries(after: 2).map { $0.envelope.string("note") } == ["three"])
        #expect(log.entries(after: 99).isEmpty)
    }

    @Test func anUnreadableEntryIsSkippedRatherThanFatal() throws {
        let log = try outbox()
        try log.append([envelope("good")])
        try Data("not json".utf8)
            .write(to: log.directory.appendingPathComponent("me__0000009999__x.json"))

        #expect(log.entries(after: 0).count == 1)
    }
}

struct SyncFramingTests {
    @Test func aFramedMessageRoundTrips() {
        var buffer = SyncFraming.frame(Data("hello".utf8))
        #expect(SyncFraming.nextMessage(from: &buffer) == Data("hello".utf8))
        #expect(buffer.isEmpty)
    }

    @Test func twoMessagesInOneBufferAreSeparated() {
        // TCP is a stream: two sends can arrive as one buffer. Without framing
        // neither decodes, and the sync silently does nothing.
        var buffer = SyncFraming.frame(Data("first".utf8))
        buffer.append(SyncFraming.frame(Data("second".utf8)))

        #expect(SyncFraming.nextMessage(from: &buffer) == Data("first".utf8))
        #expect(SyncFraming.nextMessage(from: &buffer) == Data("second".utf8))
        #expect(SyncFraming.nextMessage(from: &buffer) == nil)
    }

    @Test func aPartialMessageWaitsRatherThanDecodingRubbish() {
        let whole = SyncFraming.frame(Data(repeating: 7, count: 5_000))
        var buffer = whole.prefix(1_200)          // arrived in pieces, as large ones do

        #expect(SyncFraming.nextMessage(from: &buffer) == nil)
        #expect(buffer.count == 1_200)            // nothing consumed, nothing lost

        buffer.append(whole.dropFirst(1_200))
        #expect(SyncFraming.nextMessage(from: &buffer)?.count == 5_000)
    }

    @Test func aWireExchangeRoundTripsThroughJSON() throws {
        let response = SyncWire.Response.records(
            authorID: "author-a",
            entries: [.init(sequence: 3,
                            envelope: SyncEnvelope(recordType: "Memory", id: UUID(),
                                                   authorID: "author-a", updatedAt: .now,
                                                   deletedAt: nil,
                                                   fields: ["note": .string("Kyoto")]))])
        let data = try JSONEncoder().encode(response)
        #expect(try JSONDecoder().decode(SyncWire.Response.self, from: data) == response)
    }

    @Test func bothRequestKindsSurviveTheWire() throws {
        for request in [SyncWire.Request.records(cursor: ["a": 3]),
                        SyncWire.Request.asset(id: "photo-1")] {
            let data = try JSONEncoder().encode(request)
            #expect(try JSONDecoder().decode(SyncWire.Request.self, from: data) == request)
        }
    }

    @Test func anAssetResponseCarriesBytesLargerThanOneReceiveBuffer() throws {
        // 400KB is a normal photo and far more than a single `receive` returns,
        // so this only works if framing reassembles across chunks.
        let big = Data(repeating: 9, count: 400_000)
        let encoded = try JSONEncoder().encode(SyncWire.Response.asset(data: big))
        var buffer = SyncFraming.frame(encoded)
        let message = SyncFraming.nextMessage(from: &buffer)

        guard case let .asset(data)? = try message.map({
            try JSONDecoder().decode(SyncWire.Response.self, from: $0)
        }) else {
            Issue.record("expected an asset response")
            return
        }
        #expect(data?.count == 400_000)
    }
}
