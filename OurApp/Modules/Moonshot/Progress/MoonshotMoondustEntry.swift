import Foundation
import SwiftData

/// One moondust movement — earn or spend (M31). Append-only and
/// sync-shaped like every Moonshot record (§7): the balance is the sum
/// over ALL partners' rows (one couple wallet), spends are negative rows,
/// and union-merge can never conflict.
@Model
final class MoonshotMoondustEntry {
    var partnerID: String
    var amount: Int
    var reason: String
    var at: Date

    init(partnerID: String, amount: Int, reason: String) {
        self.partnerID = partnerID
        self.amount = amount
        self.reason = reason
        at = .now
    }
}
