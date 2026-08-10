import Foundation

/// A "cloud" that is a folder. Two simulators pointed at the same directory on
/// the Mac converge for real — no entitlement, no account, no network.
///
/// Deliberately dumb: one JSON file per envelope, names sorted lexicographically
/// *and* chronologically because the timestamp is fixed-width and zero-padded.
/// The cursor is simply the last filename consumed.
///
/// This is scaffolding for slice D, but it is not throwaway — it is also the
/// only way to watch replication happen before there is a CloudKit container.
struct FileCloudTransport: SyncTransport {
    let directory: URL

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    func push(_ envelopes: [SyncEnvelope]) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for envelope in envelopes {
            let data = try Self.encoder.encode(envelope)
            let name = Self.name(at: Date(), id: envelope.id)
            let final = directory.appendingPathComponent(name)
            // Written aside and renamed in: a reader listing the directory
            // mid-write would otherwise decode a truncated file and drop the
            // record silently.
            let staging = directory.appendingPathComponent(name + ".tmp")
            try data.write(to: staging, options: .atomic)
            try? FileManager.default.removeItem(at: final)
            try FileManager.default.moveItem(at: staging, to: final)
        }
    }

    func pull(since token: SyncToken?) async throws -> SyncBatch {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasSuffix(".json") }
            .filter { name in token.map { name > $0 } ?? true }
            .sorted()

        var envelopes: [SyncEnvelope] = []
        for name in names {
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)),
                  let envelope = try? Self.decoder.decode(SyncEnvelope.self, from: data)
            else { continue }   // a half-written or foreign file is skipped, never fatal
            envelopes.append(envelope)
        }
        return SyncBatch(envelopes: envelopes, token: names.last ?? token ?? "")
    }

    /// `00000001754700000.123456-<uuid>.json`. Fixed width so string ordering
    /// is time ordering — the moment it isn't, `pull(since:)` starts skipping
    /// records or replaying them forever.
    private static func name(at date: Date, id: UUID) -> String {
        String(format: "%024.6f", date.timeIntervalSince1970) + "-" + id.uuidString + ".json"
    }
}
