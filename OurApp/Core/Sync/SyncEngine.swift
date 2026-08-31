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
    /// The ids already sent whose `updatedAt` is exactly the watermark.
    ///
    /// Records written in one batch share a timestamp to the millisecond. With
    /// a strictly-greater-than test, sending some of them advances the mark to
    /// that instant and buries the rest — which is how a memory ended up on one
    /// phone and unreachable from the other. Remembering the handful at the
    /// boundary lets the test include equals without ever re-sending.
    private var pushedBoundaryKey: String { "sync.pushedBoundary.\(transport.syncIdentity)" }

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
        // **One-time repair for anything the old rule buried.**
        //
        // Records stranded under a watermark that had already moved past them
        // cannot rescue themselves: the fix above stops it happening again but
        // cannot lower a mark that is already too high. The absence of the
        // boundary key is exactly the signature of an install that ran the old
        // rule, so the first pass under the new one rescans from the beginning.
        //
        // Safe to the point of being boring: applying a record twice is a no-op
        // by construction, and there is a test that says so.
        if defaults.object(forKey: pushedBoundaryKey) == nil {
            defaults.removeObject(forKey: pushedThroughKey)
            defaults.set([String](), forKey: pushedBoundaryKey)
        }
        let through = defaults.object(forKey: pushedThroughKey) as? Date ?? .distantPast
        let boundary = Set(defaults.stringArray(forKey: pushedBoundaryKey) ?? [])
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
            for row in rows {
                let at = row.syncUpdatedAt
                let unsentAtBoundary = at == through
                    && !boundary.contains(row.syncID.uuidString)
                guard at > through || unsentAtBoundary else { continue }
                outgoing.append(row.envelope())
            }
        }
        collect(Profile.self)
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

        // **Advance only as far as we actually saw, never merely to "now".**
        //
        // Setting the mark to the clock buried anything saved around that
        // instant which this fetch happened not to see — permanently, since
        // nothing rescans below the line. Three memories written together, two
        // sent, and the third could never leave the phone.
        //
        // Clamped to `stamp` so a partner's record carrying a clock running
        // fast cannot drag the mark into our future and bury our own writes —
        // the failure this watermark was rewritten for once already.
        let observed = outgoing.map(\.updatedAt).filter { $0 <= stamp }.max() ?? through
        let mark = max(through, observed)
        // Everything sent at exactly the mark, so the next pass can include
        // equals without re-sending these.
        var atMark = outgoing.filter { $0.updatedAt == mark }.map { $0.id.uuidString }
        if mark == through { atMark.append(contentsOf: boundary) }
        defaults.set(mark, forKey: pushedThroughKey)
        defaults.set(Array(Set(atMark)), forKey: pushedBoundaryKey)
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
