import Foundation

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
}
