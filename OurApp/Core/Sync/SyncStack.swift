import Foundation
import SwiftData

/// The one sync stack for the app.
///
/// A singleton because there genuinely is one: a second `LocalPeerService`
/// would advertise a second listener under the same name on the same device,
/// and the pairing screen has to be talking to the same service that Home syncs
/// with — otherwise you would pair one object and sync with another.
@MainActor
enum SyncStack {
    static let outbox = SyncOutbox(
        directory: FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SyncOutbox", isDirectory: true),
        authorID: LocalAuthor.id())

    static let peers = LocalPeerService(outbox: outbox)

    static var transport: LocalNetworkTransport {
        LocalNetworkTransport(outbox: outbox, peers: peers, photos: MemoryPhotoStore())
    }

    /// Push and pull once, from anywhere.
    ///
    /// Sync used to tick only when the couples Home screen came to the
    /// foreground. Co-op lives inside Moonshot, so a match never synced while
    /// you were playing it: each phone kept its own match, each took "the first
    /// turn", and both sat waiting for a turn that was never sent. A feature
    /// that needs sync has to be able to ask for it.
    @discardableResult
    static func tick(context: ModelContext) async -> [String] {
        let engine = SyncEngine(context: context, transport: transport,
                                authorID: LocalAuthor.id())
        return (try? await engine.tick()) ?? []
    }
}
