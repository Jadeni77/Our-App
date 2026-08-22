import CloudKit
import Foundation
import Testing
@testable import OurApp

/// The `CKRecord` mapping, proven with no entitlement, no iCloud account and no
/// device — which is the whole reason it is a separate, pure file.
struct CloudKitEnvelopeCodecTests {
    private let zoneID = CKRecordZone.ID(zoneName: "Couple", ownerName: CKCurrentUserDefaultName)

    private func envelope(fields: [String: SyncValue] = [:],
                          deletedAt: Date? = nil) -> SyncEnvelope {
        SyncEnvelope(recordType: "CoopMatch",
                     id: UUID(),
                     authorID: "author-a",
                     updatedAt: Date(timeIntervalSinceReferenceDate: 800_000_000),
                     deletedAt: deletedAt,
                     fields: fields)
    }

    @Test func everyFieldKindSurvivesTheRoundTrip() throws {
        let original = envelope(fields: [
            "turnHolder": .string("author-b"),
            "turnIndex": .int(7),
            "ratio": .double(0.5),
            "cleared": .bool(true),
            "day": .date(Date(timeIntervalSinceReferenceDate: 700_000_000)),
            "photoIDs": .stringArray(["a", "b"]),
        ])

        let record = try CloudKitEnvelopeCodec.record(for: original, in: zoneID)
        let back = try #require(CloudKitEnvelopeCodec.envelope(from: record))
        #expect(back == original)
    }

    /// A tombstone is a value, and a record that lost it would resurrect a
    /// deleted memory on the other phone.
    @Test func aTombstoneSurvives() throws {
        let deleted = Date(timeIntervalSinceReferenceDate: 900_000_000)
        let record = try CloudKitEnvelopeCodec.record(for: envelope(deletedAt: deleted),
                                                      in: zoneID)
        #expect(CloudKitEnvelopeCodec.envelope(from: record)?.deletedAt == deleted)
    }

    /// **The record's name is the envelope's id.** It is what makes two phones
    /// writing one logical record — a co-op match, whose id is its level's id —
    /// write to a single CloudKit record instead of two that could never be
    /// reconciled.
    @Test func theRecordNameIsTheEnvelopeID() throws {
        let original = envelope()
        let record = try CloudKitEnvelopeCodec.record(for: original, in: zoneID)
        #expect(record.recordID.recordName == original.id.uuidString)
        #expect(record.recordID.zoneID == zoneID)
        #expect(record.recordType == "CoopMatch")
    }

    /// Two writes to one id must produce one record, not two.
    @Test func rewritingAnEnvelopeReusesItsRecord() throws {
        let first = envelope(fields: ["turnIndex": .int(1)])
        let record = try CloudKitEnvelopeCodec.record(for: first, in: zoneID)

        var second = first
        second.fields["turnIndex"] = .int(2)
        // Handing the server's own record back is also what keeps its change
        // tag — a save without the current tag is rejected as a conflict.
        let updated = try CloudKitEnvelopeCodec.record(for: second, in: zoneID,
                                                       existing: record)
        #expect(updated.recordID == record.recordID)
        #expect(CloudKitEnvelopeCodec.envelope(from: updated)?.fields["turnIndex"] == .int(2))
    }

    /// A shared database is not ours alone to assume things about, and one
    /// unreadable record must never stop a batch from arriving.
    @Test func aForeignOrUnreadableRecordIsSkippedRatherThanFatal() {
        let foreign = CKRecord(recordType: "SomethingElse",
                               recordID: CKRecord.ID(recordName: "not-a-uuid", zoneID: zoneID))
        #expect(CloudKitEnvelopeCodec.envelope(from: foreign) == nil)

        let wellNamedButEmpty = CKRecord(
            recordType: "CoopMatch",
            recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID))
        #expect(CloudKitEnvelopeCodec.envelope(from: wellNamedButEmpty) == nil)
    }
}
