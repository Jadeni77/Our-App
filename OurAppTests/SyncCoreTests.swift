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
        let (a, b) = try pair()
        let memory = Memory(note: "first", day: .now,
                            authorID: a.authorID, photoIDs: [])
        a.context.insert(memory)
        try a.context.save()
        try await a.engine.tick()

        memory.note = "edited after pushing"
        memory.updatedAt = Date().addingTimeInterval(60)
        try a.context.save()

        // A's own envelope comes back on the next pull. It must lose to the
        // newer local edit rather than stamping the old text back.
        try await a.engine.tick()

        #expect(try memories(a).first?.note == "edited after pushing")
        _ = b
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

    private func envelope(_ note: String) -> SyncEnvelope {
        SyncEnvelope(recordType: Memory.syncTypeName, id: UUID(),
                     authorID: "author-a", updatedAt: .now, deletedAt: nil,
                     fields: ["note": .string(note)])
    }

    @Test func envelopesRoundTripThroughARealDirectory() async throws {
        let transport = FileCloudTransport(directory: try directory())
        let sent = envelope("Kyoto")
        try await transport.push([sent])

        let batch = try await transport.pull(since: nil)
        #expect(batch.envelopes == [sent])
    }

    @Test func pullingAgainWithTheCursorReturnsNothing() async throws {
        let transport = FileCloudTransport(directory: try directory())
        try await transport.push([envelope("one")])
        let first = try await transport.pull(since: nil)

        let second = try await transport.pull(since: first.token)
        // An idle tick must not re-deliver: without this the other phone
        // re-applies the same envelopes on every foreground, forever.
        #expect(second.envelopes.isEmpty)
        #expect(second.token == first.token)
    }

    @Test func onlyEnvelopesAfterTheCursorComeBack() async throws {
        let transport = FileCloudTransport(directory: try directory())
        try await transport.push([envelope("one")])
        let first = try await transport.pull(since: nil)
        try await transport.push([envelope("two")])

        let second = try await transport.pull(since: first.token)
        #expect(second.envelopes.count == 1)
        #expect(second.envelopes.first?.string("note") == "two")
    }

    @Test func aHalfWrittenOrForeignFileIsSkippedRatherThanFatal() async throws {
        let folder = try directory()
        let transport = FileCloudTransport(directory: folder)
        try await transport.push([envelope("good")])
        try Data("not json".utf8)
            .write(to: folder.appendingPathComponent("00000000000000000000.000000-x.json"))

        // Principle 7 at the transport layer: one unreadable file must not stop
        // every other record from arriving.
        let batch = try await transport.pull(since: nil)
        #expect(batch.envelopes.count == 1)
        #expect(batch.envelopes.first?.string("note") == "good")
    }

    @Test func fileNamesSortChronologically() async throws {
        let folder = try directory()
        let transport = FileCloudTransport(directory: folder)
        for index in 0..<12 {
            try await transport.push([envelope("note-\(index)")])
        }
        let batch = try await transport.pull(since: nil)
        // Fixed-width padding is what makes string order time order. Without
        // it, "9.0" sorts after "10.0" and pull(since:) silently skips records.
        #expect(batch.envelopes.map { $0.string("note") }
                == (0..<12).map { "note-\($0)" })
    }
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
        await SyncAssetPump.upload(context: sending, transport: transport,
                                   photos: sender, defaults: defaults())

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
        let transport = LoopbackTransport(cloud: LoopbackCloud())
        let store = try photoStore()
        let id = try store.write(jpeg(), id: UUID().uuidString)

        let receiving = try context()
        receiving.insert(Memory(note: "already here", day: .now,
                                authorID: "author-a", photoIDs: [id]))
        try receiving.save()

        // Nothing was ever uploaded; if this tried to fetch it would fail. It
        // returning empty is what proves it never asked.
        #expect(await SyncAssetPump.download(context: receiving,
                                             transport: transport, photos: store).isEmpty)
    }

    @Test func uploadingIsNotRepeatedOnEveryTick() async throws {
        let transport = LoopbackTransport(cloud: LoopbackCloud())
        let store = try photoStore()
        let shared = defaults()
        let id = try store.write(jpeg(), id: UUID().uuidString)

        let sending = try context()
        sending.insert(Memory(note: "once", day: .now, authorID: "author-a", photoIDs: [id]))
        try sending.save()

        await SyncAssetPump.upload(context: sending, transport: transport,
                                   photos: store, defaults: shared)
        // Deleting the local file makes a second upload impossible to fake: if
        // it re-read and re-sent, this would have nothing to send.
        store.delete(id)
        await SyncAssetPump.upload(context: sending, transport: transport,
                                   photos: store, defaults: shared)

        #expect(try await transport.getAsset(id: id) != nil)
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
