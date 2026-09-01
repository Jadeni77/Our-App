import Foundation

/// The seam. Slice A ships two implementations and **neither touches the
/// network** — no entitlement, no paid team, nothing that needs the $99
/// program. Slice D adds a `CKSyncEngine`-backed third and deletes neither.
protocol SyncTransport: Sendable {
    /// Which channel this is, so progress through it is remembered separately.
    ///
    /// **Sync progress belongs to a transport, not to the app.** The engine
    /// records how far it has pushed and pulled; those marks describe one
    /// channel's contents and mean nothing about another. Sharing them loses
    /// records outright: a phone that ticks over the local network, then later
    /// over a shared folder, has a watermark saying everything up to now was
    /// sent — while the folder never received any of it, and a high-water mark
    /// only moves forward, so nothing rescans below it.
    ///
    /// That is exactly how a co-op turn went missing. It was pushed into the
    /// Bonjour outbox by a plain launch, the mark advanced, and the folder the
    /// other phone was reading never saw it. One phone waited forever for a
    /// shot that had already been taken.
    var syncIdentity: String { get }

    func push(_ envelopes: [SyncEnvelope]) async throws
    /// Everything the other side has written since `token`, plus a new cursor.
    func pull(since token: SyncToken?) async throws -> SyncBatch
}

extension SyncTransport {
    /// The type name is enough to tell one channel from another; transports
    /// that can point at different destinations say so themselves.
    var syncIdentity: String { String(describing: Self.self) }
}

/// An in-memory queue shared by two engines in one test process. This is how
/// the merge rules are proven, and it stays useful as a test double long after
/// a real transport exists.
actor LoopbackCloud {
    private var envelopes: [(sequence: Int, envelope: SyncEnvelope)] = []
    private var nextSequence = 0
    private var assets: [String: Data] = [:]

    func putAsset(_ data: Data, id: String) { assets[id] = data }
    func asset(id: String) -> Data? { assets[id] }

    func push(_ incoming: [SyncEnvelope]) {
        for envelope in incoming {
            envelopes.append((nextSequence, envelope))
            nextSequence += 1
        }
    }

    func pull(since token: SyncToken?) -> SyncBatch {
        let after = token.flatMap(Int.init) ?? -1
        let fresh = envelopes.filter { $0.sequence > after }
        // The cursor advances even when nothing came back, so an idle tick
        // doesn't re-deliver the same batch forever.
        let cursor = fresh.last?.sequence ?? after
        return SyncBatch(envelopes: fresh.map(\.envelope), token: String(cursor))
    }
}

struct LoopbackTransport: SyncTransport, SyncAssetTransport {
    let cloud: LoopbackCloud

    func putAsset(_ data: Data, id: String) async throws {
        await cloud.putAsset(data, id: id)
    }

    func getAsset(id: String) async throws -> Data? {
        await cloud.asset(id: id)
    }

    func hasAsset(id: String) async -> Bool {
        await cloud.asset(id: id) != nil
    }

    func push(_ envelopes: [SyncEnvelope]) async throws {
        await cloud.push(envelopes)
    }

    func pull(since token: SyncToken?) async throws -> SyncBatch {
        await cloud.pull(since: token)
    }
}
