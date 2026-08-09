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

    @Test func specialDatesIsTheOnlyLiveEntryAndCarriesABadge() {
        let live = HubCatalog.entries.filter(\.isReady)
        #expect(live.map(\.id) == ["special-dates"])
        #expect(live.first?.makeBadge != nil)
    }

    @Test func comingSoonEntriesExplainThemselvesAndCarryNoBadge() {
        for entry in HubCatalog.entries where !entry.isReady {
            guard case .comingSoon = entry.kind else {
                Issue.record("\(entry.id) is not ready but isn't .comingSoon")
                continue
            }
            #expect(entry.makeBadge == nil)
        }
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
