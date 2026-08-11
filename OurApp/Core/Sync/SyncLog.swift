import Foundation

/// How a replicated envelope is named on disk: `<author>__<0000000007>__<uuid>`.
///
/// Shared by the folder transport and the outbox behind the network transport,
/// because they order records the same way — **per writer, never by clock.** A
/// wall clock cannot order two devices; the first version of the folder
/// transport tried, and a partner running a few minutes behind was skipped
/// forever (P24).
enum SyncLogEntryName {
    /// A separator a UUID cannot contain, so parsing can't be confused by one.
    private static let separator = "__"

    static func make(author: String, sequence: Int, id: UUID) -> String {
        "\(author)\(separator)\(String(format: "%010d", sequence))\(separator)\(id.uuidString).json"
    }

    static func parse(_ name: String) -> (author: String, sequence: Int)? {
        let parts = name.replacingOccurrences(of: ".json", with: "")
            .components(separatedBy: separator)
        guard parts.count == 3, let sequence = Int(parts[1]) else { return nil }
        return (parts[0], sequence)
    }
}

/// This device's own append-only log of everything it has ever pushed.
///
/// The network transport needs it because a peer that was away has to be able
/// to ask for what it missed — there is no server holding the history, so each
/// device is the authority on its own.
struct SyncOutbox {
    let directory: URL
    let authorID: String

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    /// Sequence continues from what is on disk rather than from memory, so a
    /// relaunched app doesn't restart at 1 and overwrite its own history.
    func highestSequence() -> Int {
        names().compactMap(SyncLogEntryName.parse).map(\.sequence).max() ?? 0
    }

    @discardableResult
    func append(_ envelopes: [SyncEnvelope]) throws -> Int {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var sequence = highestSequence()
        for envelope in envelopes {
            sequence += 1
            let name = SyncLogEntryName.make(author: authorID, sequence: sequence, id: envelope.id)
            let staging = directory.appendingPathComponent(name + ".tmp")
            try Self.encoder.encode(envelope).write(to: staging, options: .atomic)
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            try FileManager.default.moveItem(at: staging,
                                             to: directory.appendingPathComponent(name))
        }
        return sequence
    }

    /// Everything written after `sequence`, oldest first.
    func entries(after sequence: Int) -> [(sequence: Int, envelope: SyncEnvelope)] {
        names()
            .compactMap { name -> (Int, SyncEnvelope)? in
                guard let parsed = SyncLogEntryName.parse(name), parsed.sequence > sequence,
                      let data = try? Data(contentsOf: directory.appendingPathComponent(name)),
                      let envelope = try? Self.decoder.decode(SyncEnvelope.self, from: data)
                else { return nil }   // unreadable entry skipped, never fatal
                return (parsed.sequence, envelope)
            }
            .sorted { $0.0 < $1.0 }
            .map { (sequence: $0.0, envelope: $0.1) }
    }

    private func names() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasSuffix(".json") }
    }
}
