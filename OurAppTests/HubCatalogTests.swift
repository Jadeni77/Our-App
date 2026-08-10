import Foundation
import Testing
@testable import OurApp

@MainActor
struct HubCatalogTests {
    @Test func catalogShipsThreeEntriesWithUniqueIDs() {
        let ids = HubCatalog.entries.map(\.id)
        #expect(ids == ["special-dates", "daily-question", "memories"])
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyEntryIsLiveAndBadgesOnlyWhereThereIsSomethingToSay() {
        // Computed outside the macro: `allSatisfy` is `rethrows`, and `#expect`
        // treats that as throwing.
        let allLive = HubCatalog.entries.allSatisfy(\.isReady)
        #expect(allLive)

        let badged = HubCatalog.entries.filter { $0.makeBadge != nil }.map(\.id)
        // Special Dates has an approaching date; Daily Question has an
        // unanswered day. Memories has nothing that expires.
        #expect(badged == ["special-dates", "daily-question"])
    }

    @Test func lookupFindsKnownIDsAndRejectsUnknownOnes() {
        #expect(HubCatalog.entry("special-dates")?.icon == .specialDates)
        #expect(HubCatalog.entry("nope") == nil)
    }

    @Test func everyEntryCarriesADistinctIcon() {
        let icons = HubCatalog.entries.map(\.icon)
        #expect(icons == [.specialDates, .dailyQuestion, .memories])
        // Distinctness of the *icons* — a copy-pasted fourth entry reusing an
        // existing one would otherwise only trip the literal above, and the
        // tempting "fix" for that is to edit the literal to match.
        #expect(Set(icons).count == icons.count)
    }
}
