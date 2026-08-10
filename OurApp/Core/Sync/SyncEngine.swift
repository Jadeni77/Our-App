import Foundation
import SwiftData

/// Push what changed, pull what arrived, apply it.
///
/// Called explicitly — on foreground and after a write. **No timers and no
/// background modes**, both of which need entitlements this slice is
/// specifically designed not to need.
@MainActor
final class SyncEngine {
    private enum Keys {
        static let pullToken = "sync.pullToken"
        static let pushedThrough = "sync.pushedThrough"
    }

    private let context: ModelContext
    private let transport: any SyncTransport
    private let authorID: String
    private let defaults: UserDefaults

    init(context: ModelContext,
         transport: any SyncTransport,
         authorID: String,
         defaults: UserDefaults = .standard) {
        self.context = context
        self.transport = transport
        self.authorID = authorID
        self.defaults = defaults
    }

    /// - Returns: photo ids that landed this tick, so a view can drop the
    ///   cached misses standing in for them.
    @discardableResult
    func tick() async throws -> [String] {
        try await push()
        try await pull()
        // Records first, always. A memory's note and date are worth having
        // immediately; the picture filling in a moment later is a far better
        // experience than a timeline that waits on megabytes.
        guard let assets = transport as? any SyncAssetTransport else { return [] }
        await SyncAssetPump.upload(context: context, transport: assets, defaults: defaults)
        return await SyncAssetPump.download(context: context, transport: assets,
                                            photos: MemoryPhotoStore())
    }

    /// "Changed since last push" is tracked by `updatedAt` rather than a dirty
    /// flag: every write already bumps it, and a second source of truth is a
    /// second thing to get out of step. It is mildly vulnerable to clock skew
    /// between two phones — slice D replaces the cursor with CloudKit's own
    /// change tokens, which is the correct fix rather than a workaround.
    private func push() async throws {
        let through = defaults.object(forKey: Keys.pushedThrough) as? Date ?? .distantPast
        var outgoing: [SyncEnvelope] = []
        var newest = through

        func collect<T: PersistentModel & SyncableRecord>(_ type: T.Type) {
            guard let rows = try? context.fetch(FetchDescriptor<T>()) else { return }
            for row in rows where row.syncUpdatedAt > through {
                outgoing.append(row.envelope())
                newest = max(newest, row.syncUpdatedAt)
            }
        }
        collect(SpecialDate.self)
        collect(QuestionAnswer.self)
        collect(Memory.self)
        collect(CheckIn.self)

        guard !outgoing.isEmpty else { return }
        try await transport.push(outgoing)
        defaults.set(newest, forKey: Keys.pushedThrough)
    }

    private func pull() async throws {
        let batch = try await transport.pull(since: defaults.string(forKey: Keys.pullToken))
        var changed = false
        for envelope in batch.envelopes {
            // Our own envelopes come back on the next pull. Applying one is a
            // no-op by construction (equal timestamp, equal author, so it never
            // supersedes) rather than by a filter somebody has to remember.
            if SyncApply.apply(envelope, in: context, localAuthorID: authorID) {
                changed = true
            }
        }
        if changed { try? context.save() }
        // The cursor advances even on an empty batch, so an idle tick doesn't
        // re-deliver the same envelopes forever.
        defaults.set(batch.token, forKey: Keys.pullToken)
    }
}
