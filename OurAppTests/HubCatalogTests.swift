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
        #expect(HubCatalog.entry("special-dates")?.emoji == "📅")
        #expect(HubCatalog.entry("nope") == nil)
    }
}
