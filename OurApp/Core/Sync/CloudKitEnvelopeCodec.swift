import CloudKit
import Foundation

/// `SyncEnvelope` ⟷ `CKRecord`.
///
/// **Pure, and separated from anything that touches the network**, so the part
/// that can be wrong in a way you only discover on two real phones is as small
/// as possible. This file needs no entitlement, no iCloud account and no device
/// to prove — which is why it is the first thing built in this slice.
///
/// The fields dictionary travels as **one JSON blob** rather than as individual
/// `CKRecord` fields. That looks lazy and is deliberate:
///
/// - Nothing queries these records. They are fetched by change token, never by
///   predicate, so per-field storage would buy a capability nobody uses.
/// - CloudKit infers a schema from the first record of each type it ever sees,
///   and a field whose type is inferred wrongly is a production migration to
///   undo. One `Data` field has no such failure mode.
/// - `SyncValue` is already `Codable` and already round-trips through JSON
///   between two simulators, tested. Reusing that is one encoding to trust
///   instead of two.
///
/// What stays native is what CloudKit or a human might need to *read*:
/// authorship and the two timestamps.
enum CloudKitEnvelopeCodec {
    enum Key {
        static let authorID = "authorID"
        static let updatedAt = "updatedAt"
        static let deletedAt = "deletedAt"
        static let payload = "payload"
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    /// The record's name **is** the envelope's id.
    ///
    /// Not a detail: it is what makes two phones writing the same logical
    /// record — a co-op match, whose id is its level's id — write to *one*
    /// CloudKit record rather than two that could never be reconciled. The same
    /// property the local merge already depends on, carried to the server.
    static func recordID(for id: UUID, in zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    static func record(for envelope: SyncEnvelope,
                       in zoneID: CKRecordZone.ID,
                       existing: CKRecord? = nil) throws -> CKRecord {
        // Mutating the record the server handed back, when there is one, is
        // what keeps its change tag — and a save without the current tag is
        // rejected as a conflict.
        let record = existing ?? CKRecord(recordType: envelope.recordType,
                                          recordID: recordID(for: envelope.id, in: zoneID))
        record[Key.authorID] = envelope.authorID as CKRecordValue
        record[Key.updatedAt] = envelope.updatedAt as CKRecordValue
        record[Key.deletedAt] = envelope.deletedAt as CKRecordValue?
        record[Key.payload] = try encoder.encode(envelope.fields) as CKRecordValue
        return record
    }

    /// - Returns: nil for a record this app did not write, or one whose payload
    ///   it cannot read. Both are skipped rather than fatal: a shared database
    ///   is not ours alone to assume things about, and one unreadable record
    ///   must never stop the rest of a batch from arriving.
    static func envelope(from record: CKRecord) -> SyncEnvelope? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let authorID = record[Key.authorID] as? String,
              let updatedAt = record[Key.updatedAt] as? Date,
              let payload = record[Key.payload] as? Data,
              let fields = try? decoder.decode([String: SyncValue].self, from: payload)
        else { return nil }

        return SyncEnvelope(recordType: record.recordType,
                            id: id,
                            authorID: authorID,
                            updatedAt: updatedAt,
                            deletedAt: record[Key.deletedAt] as? Date,
                            fields: fields)
    }
}
