import Foundation

/// Sync over the local network — the third `SyncTransport`, and the first that
/// is a real network rather than a stand-in.
///
/// **No entitlement, no paid Apple team, no CloudKit.** Local networking is an
/// `Info.plist` declaration rather than a capability, which is why this works
/// where slice D does not.
///
/// Its honest limit: both phones must be on the same network with the app open.
/// It proves replication over a socket; it is not a substitute for a cloud that
/// holds records while you are apart.
struct LocalNetworkTransport: SyncTransport, SyncAssetTransport {
    let outbox: SyncOutbox
    let peers: LocalPeerService
    let photos: MemoryPhotoStore

    /// Pushing is purely local: append to our own log. Peers pull from it when
    /// they next ask, so a partner who is away misses nothing — the history is
    /// on the device that wrote it.
    /// Appending is purely local and happens whether or not we are paired, so
    /// that pairing later hands the partner our whole history rather than only
    /// what came after. `start()` decides for itself whether advertising is
    /// warranted.
    func push(_ envelopes: [SyncEnvelope]) async throws {
        try outbox.append(envelopes)
        await peers.start()
    }

    func pull(since token: SyncToken?) async throws -> SyncBatch {
        await peers.start()
        let cursor = Self.cursor(from: token)
        let result = await peers.exchange(cursor: cursor)
        return SyncBatch(envelopes: result.envelopes, token: Self.token(from: result.cursor))
    }

    // MARK: - Assets

    /// **There is no upload.** In a peer-to-peer model the phone holding the
    /// picture is the phone that answers for it, so `hasAsset` reporting what
    /// this device already holds makes the pump's upload pass a no-op for our
    /// own photos — which is exactly right, and needs no special case in it.
    func putAsset(_ data: Data, id: String) async throws {}

    func hasAsset(id: String) async -> Bool {
        photos.has(id)
    }

    func getAsset(id: String) async throws -> Data? {
        await peers.asset(id: id)
    }

    /// The token is a map of writer → last sequence, exactly as the folder
    /// transport learned to do: one writer falling behind must not hide
    /// another's newer records (P24).
    static func cursor(from token: SyncToken?) -> [String: Int] {
        guard let token, let data = token.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return [:] }
        return map
    }

    static func token(from cursor: [String: Int]) -> SyncToken {
        guard let data = try? JSONEncoder().encode(cursor) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
