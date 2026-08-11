import Foundation

/// Photo bytes, moved over the same transport as the records.
///
/// Kept separate from `SyncEnvelope` on purpose: a record is a few hundred
/// bytes and must arrive promptly, an asset is hundreds of kilobytes and can
/// arrive late. Folding them together would make every record wait behind a
/// picture — and the memory's note and date are the part worth having first.
protocol SyncAssetTransport: Sendable {
    /// Uploads bytes under a stable id. Uploading an id that already exists is
    /// a no-op, not an error — ids are content-stable, so a second upload can
    /// only be a retry.
    func putAsset(_ data: Data, id: String) async throws
    /// `nil` when the other phone hasn't uploaded it yet, which is normal and
    /// not a failure — records outrun their pictures by design.
    func getAsset(id: String) async throws -> Data?
    /// Whether the cloud already holds it. Asked instead of remembering, so
    /// "what still needs uploading" is derived state rather than a list that
    /// can go stale.
    func hasAsset(id: String) async -> Bool
}
