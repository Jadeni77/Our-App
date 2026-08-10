import Foundation

/// Which replication rules a record type plays by.
///
/// The split comes from the owner's answer about game progress — *"the regular
/// mode don't share, but each device should be able to see the other's
/// progress"* — and it is what keeps the merge engine small.
enum SyncCategory {
    /// One timeline both people write into. Needs a conflict policy.
    case shared
    /// Each author owns their rows; the other phone stores and displays them
    /// and never writes them. **A stronger guarantee than `shared`, not a
    /// weaker one** — two authors never touch the same record, so there is
    /// nothing to resolve.
    case mirrored
}

/// A field value, spelled out rather than left to `Any`.
enum SyncValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case date(Date)
    case stringArray([String])
}

/// One record, in transit. Transport-agnostic on purpose: the same struct goes
/// through an in-memory queue in tests, a JSON file between two simulators, and
/// a `CKRecord` when slice D lands.
///
/// **Fields are declared, never reflected.** A property that isn't listed
/// doesn't sync — which is the point. The failure mode of reflection is a field
/// silently travelling, or silently not travelling, and nobody noticing until
/// the data is wrong on both phones.
struct SyncEnvelope: Codable, Equatable {
    var recordType: String
    var id: UUID
    var authorID: String
    var updatedAt: Date
    var deletedAt: Date?
    var fields: [String: SyncValue]
}

typealias SyncToken = String

struct SyncBatch: Equatable {
    var envelopes: [SyncEnvelope]
    var token: SyncToken
}

/// Records describe themselves; the core moves them (§7 — modules never touch
/// the network).
@MainActor
protocol SyncableRecord {
    static var syncTypeName: String { get }
    static var syncCategory: SyncCategory { get }
    var syncID: UUID { get }
    var syncAuthorID: String { get }
    var syncUpdatedAt: Date { get }
    var syncDeletedAt: Date? { get }
    func syncFields() -> [String: SyncValue]
}

extension SyncableRecord {
    func envelope() -> SyncEnvelope {
        SyncEnvelope(recordType: Self.syncTypeName,
                     id: syncID,
                     authorID: syncAuthorID,
                     updatedAt: syncUpdatedAt,
                     deletedAt: syncDeletedAt,
                     fields: syncFields())
    }
}

extension SyncEnvelope {
    /// Last-writer-wins, **with a deterministic tiebreak on `authorID`**.
    ///
    /// The tiebreak is not pedantry. LWW without one is *not convergent*: two
    /// phones handed the same pair of edits can each keep their own, disagree
    /// forever, and never surface a conflict anybody could notice. Equal
    /// timestamps are not hypothetical here either — a seeded or scripted write
    /// produces them easily.
    func supersedes(_ other: SyncEnvelope) -> Bool {
        if updatedAt != other.updatedAt { return updatedAt > other.updatedAt }
        return authorID > other.authorID
    }
}
