import Foundation
import SwiftData

/// One coach moment seen by one partner (M25). Append-only — sync-shaped
/// like every Moonshot record (§7): rows merge by union, never conflict.
@Model
final class MoonshotCoachSeen {
    var partnerID: String = ""
    var momentKey: String = ""
    var seenAt: Date = Date.now

    init(partnerID: String, momentKey: String) {
        self.partnerID = partnerID
        self.momentKey = momentKey
        seenAt = .now
    }
}
