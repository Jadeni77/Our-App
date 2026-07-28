import Foundation
import SwiftData

/// One completed decision, recorded silently on every Agree (decision F4).
/// No UI reads this in v1 — it seeds the future history module and smarter picks.
@Model
final class DecisionRecord {
    var date: Date
    var cuisineChosen: String

    init(date: Date = .now, cuisineChosen: String) {
        self.date = date
        self.cuisineChosen = cuisineChosen
    }
}
