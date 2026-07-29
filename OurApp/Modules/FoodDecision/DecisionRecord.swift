import Foundation
import SwiftData

/// One completed decision, recorded silently on every Agree (decision F4).
/// No UI reads this in v1 — it seeds the future history module and smarter picks.
@Model
final class DecisionRecord {
    var date: Date
    var cuisineChosen: String
    /// Stable pool id (F6) so history survives language switches; nil for
    /// free-form typed cuisines and for all v1-era records (additive migration).
    var cuisineID: String?

    init(date: Date = .now, cuisineChosen: String, cuisineID: String? = nil) {
        self.date = date
        self.cuisineChosen = cuisineChosen
        self.cuisineID = cuisineID
    }
}
