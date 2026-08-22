import Foundation

/// A "cloud" that is a folder. Two simulators pointed at the same directory on
/// the Mac converge for real — no entitlement, no account, no network.
///
/// **Ordering is per writer, never by clock.** The first version stamped each
/// filename with `Date()` and kept a single high-water cursor. Because a tick
/// pushes before it pulls, every tick advanced your cursor past your *own*
/// newest write — so a partner whose clock ran even slightly behind wrote files
/// that sorted below your cursor and were skipped **forever**, silently, with
/// no error and no retry. Two simulators hide this completely, because they
/// share the host's clock.
///
/// So each writer keeps its own sequence and the cursor is a map of
/// writer → last sequence consumed. No clock is involved anywhere.
struct FileCloudTransport: SyncTransport, SyncAssetTransport {
    let directory: URL
    /// Whose sequence to advance when pushing. Files from other writers are
    /// what `pull` returns.
    let authorID: String

    /// Assets live in their own subdirectory so `pull(since:)`, which lists the
    /// records directory, never has to filter megabytes of JPEG out of its way.
    private var assetsDirectory: URL { directory.appendingPathComponent("assets", isDirectory: true) }

    /// Includes the folder: a different folder is a different cloud, and
    /// pointing at a fresh one should hand it everything rather than assume it
    /// already has what the last one did.
    var syncIdentity: String { "file:\(directory.path)" }

    func putAsset(_ data: Data, id: String) async throws {
        try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
        let final = assetsDirectory.appendingPathComponent("\(id).jpg")
        guard !FileManager.default.fileExists(atPath: final.path) else { return }
        let staging = assetsDirectory.appendingPathComponent("\(id).jpg.tmp")
        try data.write(to: staging, options: .atomic)
        try FileManager.default.moveItem(at: staging, to: final)
    }

    func getAsset(id: String) async throws -> Data? {
        try? Data(contentsOf: assetsDirectory.appendingPathComponent("\(id).jpg"))
    }

    func hasAsset(id: String) async -> Bool {
        FileManager.default.fileExists(
            atPath: assetsDirectory.appendingPathComponent("\(id).jpg").path)
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    func push(_ envelopes: [SyncEnvelope]) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var sequence = highestSequence(for: authorID) + 1
        for envelope in envelopes {
            let data = try Self.encoder.encode(envelope)
            let name = Self.name(author: authorID, sequence: sequence, id: envelope.id)
            sequence += 1
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
        var cursor = Self.cursor(from: token)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasSuffix(".json") }
            .sorted()

        // **A cursor can outlive the log it points into.**
        //
        // Sequences only ever climb within one log, so a writer whose highest
        // file sits *below* our cursor is not a writer who has gone quiet — it
        // is a different log wearing the same name. That happens whenever this
        // folder is wiped and recreated, which the two-phone script does on
        // every run, and the effect is total and silent: the cursor stays above
        // everything the partner writes, so every record they send is skipped
        // forever. Observed at cursor 21 against files numbered 3 and 4, with
        // one phone waiting on a turn the other had already taken.
        //
        // Rewinding is safe in a way that guessing never is: applying a record
        // twice is a no-op by construction, and there is a test that says so.
        var highest: [String: Int] = [:]
        for name in names {
            guard let (author, sequence) = Self.parse(name) else { continue }
            highest[author] = max(highest[author] ?? 0, sequence)
        }
        for (author, mark) in cursor where mark > (highest[author] ?? 0) {
            cursor[author] = 0
        }

        var envelopes: [SyncEnvelope] = []
        for name in names {
            guard let (author, sequence) = Self.parse(name) else { continue }
            // Your own writes are never pulled back. They used to be, and they
            // were what dragged the cursor past the other phone's files.
            guard author != authorID, sequence > (cursor[author] ?? 0) else { continue }
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)),
                  let envelope = try? Self.decoder.decode(SyncEnvelope.self, from: data)
            else { continue }   // a half-written or foreign file is skipped, never fatal
            envelopes.append(envelope)
            cursor[author] = sequence
        }
        return SyncBatch(envelopes: envelopes, token: Self.token(from: cursor))
    }

    private func highestSequence(for author: String) -> Int {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .compactMap(Self.parse)
            .filter { $0.author == author }
            .map(\.sequence)
            .max() ?? 0
    }

    /// `<author>__<0000000007>__<uuid>.json`. The double underscore is a
    /// separator a UUID cannot contain, so parsing can't be confused by one.
    private static func name(author: String, sequence: Int, id: UUID) -> String {
        "\(author)__\(String(format: "%010d", sequence))__\(id.uuidString).json"
    }

    private static func parse(_ name: String) -> (author: String, sequence: Int)? {
        let parts = name.replacingOccurrences(of: ".json", with: "").components(separatedBy: "__")
        guard parts.count == 3, let sequence = Int(parts[1]) else { return nil }
        return (parts[0], sequence)
    }

    /// The token is a map, not a high-water string: one writer falling behind
    /// must not hide another writer's newer records.
    private static func cursor(from token: SyncToken?) -> [String: Int] {
        guard let token, let data = token.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return [:] }
        return map
    }

    private static func token(from cursor: [String: Int]) -> SyncToken {
        guard let data = try? JSONEncoder().encode(cursor) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
