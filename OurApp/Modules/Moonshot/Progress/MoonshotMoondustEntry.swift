import Foundation
import SwiftData

/// One moondust movement — earn or spend (M31). Append-only and
/// sync-shaped like every Moonshot record (§7): the balance is the sum
/// over ALL partners' rows (one couple wallet), spends are negative rows.
/// The unique id is the union-merge dedup key — a summed ledger is the
/// one record type that duplicates corrupt silently (review finding).
/// The local spend guard keeps THIS device's ledger non-negative; two
/// devices spending offline can still union below zero, and slice (d)
/// owns that reconciliation.
@Model
final class MoonshotMoondustEntry {
    @Attribute(.unique) var id: UUID
    var partnerID: String
    var amount: Int
    var reason: String
    var at: Date

    init(partnerID: String, amount: Int, reason: String) {
        id = UUID()
        self.partnerID = partnerID
        self.amount = amount
        self.reason = reason
        at = .now
    }
}
