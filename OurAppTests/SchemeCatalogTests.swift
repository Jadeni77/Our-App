import Foundation
import Testing
@testable import OurApp

struct SchemeCatalogTests {
    @Test func candidatesCoverSquashInitialsAndFirstWord() {
        #expect(SchemeCatalog.candidates(from: "Honor of Kings")
                == ["honorofkings://", "hok://", "honor://"])
        #expect(SchemeCatalog.candidates(from: "Minecraft") == ["minecraft://"])
        #expect(SchemeCatalog.candidates(from: "第五人格") == [])
    }

    @Test func candidatesPreferTheSubtitleOfAStoreStyleTitle() {
        // Store titles wrap the everyday name: "League of Legends: Wild Rift".
        // The subtitle's squash is the strongest guess, so it goes first.
        #expect(SchemeCatalog.candidates(from: "League of Legends: Wild Rift")
                == ["wildrift://", "leagueoflegendswildrift://", "lolwr://",
                    "wr://", "league://"])
    }

    @Test func verifiedSchemesMatchByContainment() {
        #expect(SchemeCatalog.verified(for: "League of Legends: Wild Rift")
                == "wildrift://")
        #expect(SchemeCatalog.verified(for: "Wild Rift") == "wildrift://")
        #expect(SchemeCatalog.verified(for: "Clash of Clans") == "clashofclans://")
        #expect(SchemeCatalog.verified(for: "Candy Crush Saga") == nil)
    }
}
