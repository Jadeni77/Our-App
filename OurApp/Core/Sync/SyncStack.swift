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

    /// The transport this app is actually using — **decided here, once.**
    ///
    /// Home used to make this choice for itself, and in a debug run pointed at
    /// a shared folder it chose `FileCloudTransport` while everything else got
    /// the Bonjour one from here. So Home replicated through the folder and
    /// co-op pushed turns at a listener on the other side of a channel nobody
    /// was reading: both phones kept their own match and both sat waiting.
    ///
    /// Two answers to "how does this app sync" is one too many. A caller asks
    /// for the transport; it does not get to pick.
    static var transport: any SyncTransport {
        #if DEBUG
        if let directory = FakeCloudLaunch.directory, !FakeCloudLaunch.usesLocalNetwork {
            return FileCloudTransport(directory: directory, authorID: LocalAuthor.id())
        }
        #endif
        return LocalNetworkTransport(outbox: outbox, peers: peers, photos: MemoryPhotoStore())
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
