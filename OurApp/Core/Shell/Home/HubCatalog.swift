import SwiftUI

/// The one place hub entries are declared. Adding a sub-page is one row here
/// plus the page itself — Home needs no changes.
@MainActor
enum HubCatalog {
    static let entries: [HubEntry] = [
        HubEntry(id: "special-dates",
                 name: "Special Dates",
                 icon: .specialDates,
                 kind: .page { AnyView(SpecialDatesView()) },
                 makeBadge: { AnyView(SpecialDatesBadge()) }),
        HubEntry(id: "daily-question",
                 name: "Daily Question",
                 icon: .dailyQuestion,
                 kind: .page { AnyView(DailyQuestionView()) },
                 makeBadge: { AnyView(DailyQuestionBadge()) }),
        HubEntry(id: "memories",
                 name: "Memories",
                 icon: .memories,
                 kind: .comingSoon("When our phones can talk to each other")),
    ]

    static func entry(_ id: String) -> HubEntry? {
        entries.first { $0.id == id }
    }
}
