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
    private var waitingForPeers: [CheckedContinuation<Void, Never>] = []

    init(outbox: SyncOutbox, photos: MemoryPhotoStore = MemoryPhotoStore()) {
        self.outbox = outbox
        self.photos = photos
    }

    /// Discovery is not instant, and a tick fires the moment Home appears. The
    /// first exchange after launch would otherwise find an empty peer list and
    /// quietly do nothing — which looks exactly like sync being broken.
    private func awaitPeers(timeout: Duration = .seconds(6)) async {
        guard peers.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { try? await Task.sleep(for: timeout) }
            group.addTask { [self] in
                await withCheckedContinuation { continuation in
                    Task { await self.enqueue(continuation) }
                }
            }
            await group.next()
            group.cancelAll()
        }
    }

    private func enqueue(_ continuation: CheckedContinuation<Void, Never>) {
        if peers.isEmpty {
            waitingForPeers.append(continuation)
        } else {
            continuation.resume()
        }
    }

    func start() {
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
        defer {
            if !peers.isEmpty {
                let waiting = waitingForPeers
                waitingForPeers = []
                for continuation in waiting { continuation.resume() }
            }
            SyncTrace.write("peers: \(peers.count)")
        }
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
                  let request = try? JSONDecoder().decode(SyncWire.Request.self, from: data)
            else { connection.cancel(); return }

            Task {
                let response = await self.response(for: request)
                guard let payload = try? JSONEncoder().encode(response) else {
                    connection.cancel(); return
                }
                connection.send(content: SyncFraming.frame(payload),
                                completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }

    private func response(for request: SyncWire.Request) -> SyncWire.Response {
        switch request {
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
                      to peer: NWEndpoint) async -> SyncWire.Response? {
        guard let payload = try? JSONEncoder().encode(request) else { return nil }
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
