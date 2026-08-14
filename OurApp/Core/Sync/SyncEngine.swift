import Foundation
import OSLog
import SwiftData

/// Push what changed, pull what arrived, apply it.
///
/// Called explicitly — on foreground and after a write. **No timers and no
/// background modes**, both of which need entitlements this slice is
/// specifically designed not to need.
@MainActor
final class SyncEngine {
    /// **Per transport.** Both marks describe progress through one channel and
    /// are meaningless about another; sharing them means a record pushed into
    /// one is treated as already sent to all of them. See `syncIdentity`.
    private var pullTokenKey: String { "sync.pullToken.\(transport.syncIdentity)" }
    private var pushedThroughKey: String { "sync.pushedThrough.\(transport.syncIdentity)" }

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
        await SyncAssetPump.upload(context: context, transport: assets)
        return await SyncAssetPump.download(context: context, transport: assets,
                                            photos: MemoryPhotoStore())
    }

    /// "Changed since last push" is tracked by `updatedAt` rather than a dirty
    /// flag: every write already bumps it, and a second source of truth is a
    /// second thing to get out of step. It is mildly vulnerable to clock skew
    /// between two phones — slice D replaces the cursor with CloudKit's own
    /// change tokens, which is the correct fix rather than a workaround.
    private func push() async throws {
        let through = defaults.object(forKey: pushedThroughKey) as? Date ?? .distantPast
        // **This phone's clock, not any record's timestamp.**
        //
        // The watermark used to be `max(updatedAt)` over everything collected —
        // including rows that had arrived *from the other phone*, which carry
        // the other phone's clock. A partner running ten minutes fast therefore
        // pushed its watermark ten minutes into this phone's future, and every
        // local write for the next ten minutes fell below it and **was never
        // pushed at all**. Not delayed: a high-water mark only moves forward and
        // nothing rescans below it.
        //
        // Filtering by author instead would be wrong: shared records can be
        // edited by whoever didn't create them, and those edits must travel.
        let stamp = Date()
        var outgoing: [SyncEnvelope] = []

        func collect<T: PersistentModel & SyncableRecord>(_ type: T.Type) {
            guard let rows = try? context.fetch(FetchDescriptor<T>()) else { return }
            for row in rows where row.syncUpdatedAt > through {
                outgoing.append(row.envelope())
            }
        }
        collect(SpecialDate.self)
        collect(QuestionAnswer.self)
        collect(Memory.self)
        collect(CheckIn.self)
        collect(CoopLevelResult.self)
        collect(CoopMatch.self)
        collect(CoopTurn.self)
        collect(MoonshotLevelResult.self)

        guard !outgoing.isEmpty else { return }
        try await transport.push(outgoing)
        defaults.set(stamp, forKey: pushedThroughKey)
    }

    private func pull() async throws {
        let batch = try await transport.pull(since: defaults.string(forKey: pullTokenKey))
        var changed = false
        for envelope in batch.envelopes {
            // Our own envelopes come back on the next pull. Applying one is a
            // no-op by construction (equal timestamp, equal author, so it never
            // supersedes) rather than by a filter somebody has to remember.
            if SyncApply.apply(envelope, in: context, localAuthorID: authorID) {
                changed = true
            }
        }
        // **The cursor moves only once the records are durable.** Advancing it
        // after a failed save left the partner's records in memory only, with
        // the transport already past them — gone from this phone for good while
        // still present on the other, and silent. Re-delivery is safe: apply is
        // idempotent, and there is a test that says so.
        if changed {
            do {
                try context.save()
            } catch {
                Logger(subsystem: "OurApp", category: "sync")
                    .error("sync save failed, cursor held: \(error.localizedDescription)")
                return
            }
        }
        // Still advances on an empty batch, so an idle tick doesn't re-deliver
        // the same envelopes forever.
        defaults.set(batch.token, forKey: pullTokenKey)
    }
}
