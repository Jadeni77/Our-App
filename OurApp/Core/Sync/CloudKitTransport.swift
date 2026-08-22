import CloudKit
import Foundation
import OSLog

/// Replication over CloudKit — the transport that finally works between two
/// people who are not on the same network.
///
/// **The cursor is the server's, not ours.** `CKServerChangeToken` is issued by
/// CloudKit and describes CloudKit's own history. Every cursor this project
/// invented drifted from the log it pointed into — a push watermark three
/// minutes past a record that was therefore never sent, a pull cursor at 21
/// against files numbered 3 — and each time the failure was total and silent.
/// A server-issued token cannot drift, because it is not a claim about the log:
/// it *is* the log's own bookmark.
///
/// Deliberately thin. Everything that can be decided without a network lives in
/// `CloudKitEnvelopeCodec`, where it is tested; what remains here is the part
/// that only two real phones can prove, and it is kept small for that reason.
struct CloudKitTransport: SyncTransport {
    let database: CKDatabase
    let zoneID: CKRecordZone.ID

    private var log: Logger { Logger(subsystem: "OurApp", category: "cloudkit") }

    /// Scope and zone both matter: the private database is this phone's backup
    /// and the shared one is the couple's, and progress through one says
    /// nothing about the other.
    var syncIdentity: String {
        "cloudkit:\(database.databaseScope.rawValue):\(zoneID.zoneName):\(zoneID.ownerName)"
    }

    // MARK: - Push

    func push(_ envelopes: [SyncEnvelope]) async throws {
        guard !envelopes.isEmpty else { return }
        try await ensureZone()

        let records = try envelopes.map {
            try CloudKitEnvelopeCodec.record(for: $0, in: zoneID)
        }
        // **Not atomic.** One rejected record must not take the batch down with
        // it: a turn and a check-in have nothing to do with each other, and a
        // failed save is retried on the next tick anyway because "what has
        // changed" is recomputed from the store rather than remembered.
        let (saveResults, _) = try await database.modifyRecords(
            saving: records, deleting: [], savePolicy: .allKeys, atomically: false)

        var conflicted: [SyncEnvelope] = []
        for (recordID, result) in saveResults {
            guard case .failure(let error) = result else { continue }
            if let server = serverRecord(from: error) {
                // Somebody else wrote this record since we last saw it. Our
                // copy already went through the local merge — which is where
                // the rules live — so the server's copy supplies only its
                // change tag, without which a save is refused as a conflict.
                if let envelope = envelopes.first(where: {
                    CloudKitEnvelopeCodec.recordID(for: $0.id, in: zoneID) == recordID
                }) {
                    conflicted.append(envelope)
                    _ = try? await database.modifyRecords(
                        saving: [CloudKitEnvelopeCodec.record(for: envelope, in: zoneID,
                                                              existing: server)],
                        deleting: [], savePolicy: .allKeys, atomically: false)
                }
            } else {
                log.error("save failed for \(recordID.recordName): \(error.localizedDescription)")
            }
        }
        if !conflicted.isEmpty { log.info("resolved \(conflicted.count) save conflict(s)") }
    }

    // MARK: - Pull

    func pull(since token: SyncToken?) async throws -> SyncBatch {
        try await ensureZone()

        let changes: (modificationResultsByID: [CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, any Error>],
                      deletions: [CKDatabase.RecordZoneChange.Deletion],
                      changeToken: CKServerChangeToken,
                      moreComing: Bool)
        do {
            changes = try await database.recordZoneChanges(
                inZoneWith: zoneID, since: Self.token(from: token))
        } catch let error as CKError where error.code == .changeTokenExpired {
            // The server has forgotten this bookmark. Asking again from the
            // beginning is correct and cheap: applying a record twice is a
            // no-op by construction, and there is a test that says so.
            log.info("change token expired, refetching from the start")
            changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: nil)
        }

        var envelopes: [SyncEnvelope] = []
        for (_, result) in changes.modificationResultsByID {
            guard case .success(let modification) = result,
                  let envelope = CloudKitEnvelopeCodec.envelope(from: modification.record)
            else { continue }   // foreign or unreadable: skipped, never fatal
            envelopes.append(envelope)
        }
        // Deletions are not handled as deletions on purpose: this app tombstones
        // rather than removes (P21), so a record vanishing from CloudKit is not
        // something it can express, and silently dropping rows on the strength
        // of one would be a way to lose a memory for good.

        // If the new bookmark can't be stored, keep the old one. That costs a
        // redelivery next tick — harmless, since applying a record twice is a
        // no-op — where the alternative, recording no bookmark at all, would
        // refetch the entire zone every time forever.
        let bookmark = Self.string(from: changes.changeToken) ?? token ?? ""
        return SyncBatch(envelopes: envelopes, token: bookmark)
    }

    // MARK: - Zone

    /// Creating the zone is idempotent, so it is simply done rather than
    /// checked first — a check would be a second round trip that can still race.
    private func ensureZone() async throws {
        _ = try? await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)],
                                                  deleting: [])
    }

    // MARK: - Token plumbing

    /// `SyncToken` is a `String` because the rest of the engine stores it in
    /// `UserDefaults` and nothing else needed more. A change token is an opaque
    /// object, so it travels base64-encoded.
    static func string(from token: CKServerChangeToken) -> SyncToken? {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: token,
                                                           requiringSecureCoding: true)
        else { return nil }
        return data.base64EncodedString()
    }

    /// Anything unreadable becomes nil, which means "start from the beginning" —
    /// the safe direction. The opposite mistake, treating a bad token as
    /// current, is how a phone stops receiving anything at all.
    static func token(from string: SyncToken?) -> CKServerChangeToken? {
        guard let string, let data = Data(base64Encoded: string) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self,
                                                       from: data)
    }

    private func serverRecord(from error: any Error) -> CKRecord? {
        guard let ckError = error as? CKError, ckError.code == .serverRecordChanged else {
            return nil
        }
        return ckError.serverRecord
    }
}
