import Foundation
import Network
import OSLog

/// Bonjour discovery plus a one-shot request/response over TCP.
///
/// **Needs no entitlement and no paid Apple team** — local networking is an
/// `Info.plist` declaration, not a capability. Verified between two simulators
/// before any of this was written.
///
/// Each device serves its own outbox and asks peers for theirs. There is no
/// server holding the history, so a device is the only authority on what it
/// wrote — which is why the outbox is durable rather than in memory.
extension Notification.Name {
    /// Posted on the phone that *showed* the code, the moment the other accepts.
    static let syncDidPair = Notification.Name("sync.didPair")
}

actor LocalPeerService {
    static let serviceType = "_ourapp-sync._tcp"

    private let outbox: SyncOutbox
    /// Assets are served straight from this device's own photo store. There is
    /// no upload in a peer-to-peer model — the phone that has the picture is
    /// the phone that answers for it.
    private let photos: MemoryPhotoStore
    private let logger = Logger(subsystem: "OurApp", category: "sync.peer")
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var peers: [NWEndpoint] = []
    /// The code this phone is currently offering, if any. One at a time: two
    /// live codes would double an attacker's chances for no benefit.
    private var offer: SyncPairing.Offer?

    init(outbox: SyncOutbox, photos: MemoryPhotoStore = MemoryPhotoStore()) {
        self.outbox = outbox
        self.photos = photos
    }

    /// Discovery is not instant, and a tick fires the moment Home appears. The
    /// first exchange after launch would otherwise find an empty peer list and
    /// quietly do nothing — which looks exactly like sync being broken.
    ///
    /// **Polled, not signalled.** The first version raced a sleep against a
    /// `withCheckedContinuation` inside a task group and cancelled the loser —
    /// but cancelling a task does not resume a continuation, so whenever the
    /// timeout won, the group waited forever for a child that could never
    /// finish. It never showed up until a run where discovery genuinely failed,
    /// and then it hung the whole sync silently. Sleeping in a loop inside an
    /// actor yields between iterations, so `updatePeers` still gets in.
    private func awaitPeers(timeout: Duration = .seconds(8)) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while peers.isEmpty, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    /// Advertises **only** when there is a reason to: paired, or showing a code
    /// right now. An unpaired phone that never intends to pair stays invisible
    /// on every network it joins, which is what the old on/off toggle was
    /// really protecting and what replaced it had to keep protecting.
    func start() {
        guard SyncSecretStore.isPaired || offer != nil else { return }
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: .tcp)
            // The advertised name is the author id, so a peer knows whose
            // outbox it is about to ask for before it connects.
            listener.service = NWListener.Service(name: outbox.authorID, type: Self.serviceType)
            listener.newConnectionHandler = { [weak self] connection in
                Task { await self?.serve(connection) }
            }
            listener.start(queue: .global(qos: .utility))
            self.listener = listener
            SyncTrace.write("advertising \(outbox.authorID.prefix(8)), outbox at \(outbox.highestSequence())")
        } catch {
            logger.error("listener failed: \(error.localizedDescription)")
        }

        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let endpoints = results.map(\.endpoint)
            Task { await self?.updatePeers(endpoints) }
        }
        browser.start(queue: .global(qos: .utility))
        self.browser = browser
    }

    private func updatePeers(_ endpoints: [NWEndpoint]) {
        defer { SyncTrace.write("peers: \(peers.count)") }
        // Drop ourselves: we advertise under our own author id.
        peers = endpoints.filter { endpoint in
            if case let .service(name, _, _, _) = endpoint { return name != outbox.authorID }
            return false
        }
    }

    /// Asks every peer for everything after `cursor`, and merges what comes
    /// back. A peer that is unreachable is skipped, not fatal — the next tick
    /// asks again, which is the only retry this needs.
    func exchange(cursor: [String: Int]) async -> (envelopes: [SyncEnvelope], cursor: [String: Int]) {
        await awaitPeers()
        var merged = cursor
        var received: [SyncEnvelope] = []
        SyncTrace.write("exchange with \(peers.count) peer(s), cursor \(cursor)")

        for peer in peers {
            guard case let .records(authorID, entries)? =
                    await send(.records(cursor: cursor), to: peer) else {
                SyncTrace.write("no response from a peer")
                continue
            }
            SyncTrace.write("got \(entries.count) from \(authorID.prefix(8))")
            for entry in entries.sorted(by: { $0.sequence < $1.sequence }) {
                received.append(entry.envelope)
                merged[authorID] = max(merged[authorID] ?? 0, entry.sequence)
            }
        }
        return (received, merged)
    }

    /// Asks each peer in turn for one photo, stopping at the first that has it.
    func asset(id: String) async -> Data? {
        await awaitPeers()
        for peer in peers {
            if case let .asset(data)? = await send(.asset(id: id), to: peer), let data {
                return data
            }
        }
        return nil
    }

    // MARK: - Serving

    private func serve(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        receiveMessage(on: connection) { [weak self] data in
            guard let self, let data,
                  let message = try? JSONDecoder().decode(SyncWire.Message.self, from: data)
            else { connection.cancel(); return }

            Task {
                let response = await self.response(for: message)
                guard let payload = try? JSONEncoder().encode(response) else {
                    connection.cancel(); return
                }
                connection.send(content: SyncFraming.frame(payload),
                                completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }

    /// Shows a code for the other phone to type. Replaces any previous offer.
    func beginPairing() -> String {
        let fresh = SyncPairing.Offer()
        offer = fresh
        start()
        return fresh.code
    }

    func cancelPairing() {
        offer = nil
    }

    /// Types a code the other phone is showing. On success both ends hold the
    /// same secret and never use the code again.
    func pair(withCode code: String) async -> Bool {
        start()
        await awaitPeers()
        SyncTrace.write("pairing against \(peers.count) peer(s)")
        for peer in peers {
            if case let .paired(secret)? =
                await send(.pair(code: code), to: peer, signed: false) {
                SyncSecretStore.save(secret)
                return true
            }
        }
        return false
    }

    private func response(for message: SyncWire.Message) -> SyncWire.Response {
        // Pairing is the one request made before a secret exists, so it is the
        // one request that carries no proof. Everything else must prove itself.
        if case let .pair(code) = message.request {
            SyncTrace.write("pair request \(code), offer live: \(offer?.isLive() ?? false)")
            guard var live = offer, let secret = live.claim(code) else {
                offer?.burnAttempt()
                return .denied
            }
            offer = live
            SyncSecretStore.save(secret)
            offer = nil
            SyncTrace.write("paired")
            // The other phone has our secret now, but *this* phone has never
            // built a sync engine — it wasn't paired when Home appeared. Told
            // rather than polled: without this, the phone that showed the code
            // has an empty outbox and its partner syncs nothing at all.
            NotificationCenter.default.post(name: .syncDidPair, object: nil)
            return .paired(secret: secret)
        }
        guard let secret = SyncSecretStore.load(),
              let proof = message.proof,
              let body = try? JSONEncoder().encode(message.request),
              SyncAuth.verify(proof, body: body, secret: secret) else {
            SyncTrace.write("denied an unproven request")
            return .denied
        }
        return served(message.request)
    }

    private func served(_ request: SyncWire.Request) -> SyncWire.Response {
        switch request {
        case .pair:
            return .denied
        case let .records(cursor):
            let since = cursor[outbox.authorID] ?? 0
            SyncTrace.write("serving from \(since), have \(outbox.highestSequence())")
            return .records(
                authorID: outbox.authorID,
                entries: outbox.entries(after: since)
                    .map { SyncWire.Response.Entry(sequence: $0.sequence, envelope: $0.envelope) })
        case let .asset(id):
            let data = photos.storedData(for: id)
            SyncTrace.write("serving asset \(id.prefix(8)): \(data?.count ?? -1) bytes")
            return .asset(data: data)
        }
    }

    // MARK: - Asking

    private func send(_ request: SyncWire.Request,
                      to peer: NWEndpoint,
                      signed: Bool = true) async -> SyncWire.Response? {
        guard let body = try? JSONEncoder().encode(request) else { return nil }
        var proof: SyncAuth.Proof?
        if signed {
            guard let secret = SyncSecretStore.load() else { return nil }
            proof = SyncAuth.sign(body, secret: secret)
        }
        guard let payload = try? JSONEncoder()
            .encode(SyncWire.Message(request: request, proof: proof)) else { return nil }
        let connection = NWConnection(to: peer, using: .tcp)
        defer { connection.cancel() }

        return await withCheckedContinuation { continuation in
            let resumed = Resumed()
            func finish(_ response: SyncWire.Response?) {
                guard resumed.claim() else { return }
                continuation.resume(returning: response)
            }
            // A peer that vanished mid-handshake must not strand the tick.
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { finish(nil) }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: SyncFraming.frame(payload),
                                    completion: .contentProcessed { _ in })
                    receiveMessage(on: connection) { data in
                        guard let data,
                              let response = try? JSONDecoder()
                                .decode(SyncWire.Response.self, from: data)
                        else { finish(nil); return }
                        finish(response)
                    }
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))
        }
    }
}

/// One-shot latch, so a timeout racing a reply can't resume a continuation
/// twice — which traps rather than failing softly.
private final class Resumed: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

/// Reads until one whole framed message has arrived. TCP delivers a stream, so
/// a single `receive` is not a message.
private func receiveMessage(on connection: NWConnection,
                            buffer: Data = Data(),
                            completion: @escaping @Sendable (Data?) -> Void) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { chunk, _, isDone, error in
        var buffer = buffer
        if let chunk { buffer.append(chunk) }
        if let message = SyncFraming.nextMessage(from: &buffer) {
            completion(message)
            return
        }
        if isDone || error != nil {
            completion(nil)
            return
        }
        receiveMessage(on: connection, buffer: buffer, completion: completion)
    }
}
