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

    @Test func planTriesInstalledSchemesFirstAndSkipsProvenAbsentOnes() {
        // "smoba" is declared and installed → the only worthwhile attempt.
        // "honorofkings" is declared but absent → iOS already answered, so
        // firing open() at it would just prompt for nothing.
        // "hokx" isn't declared → canOpenURL can't answer, so it stays a
        // blind attempt, after the known-good one.
        let plan = SchemeCatalog.plan(
            candidates: ["honorofkings://", "hokx://", "smoba://"],
            declared: ["honorofkings", "smoba"],
            canOpen: { $0 == "smoba://" })
        #expect(plan == ["smoba://", "hokx://"])
    }

    @Test func planDropsDuplicatesAndKeepsOrderWithinGroups() {
        let plan = SchemeCatalog.plan(
            candidates: ["a://", "b://", "a://", "c://"],
            declared: ["a", "c"],
            canOpen: { $0 == "a://" })
        #expect(plan == ["a://", "b://"])   // c declared+absent → dropped
    }

    @Test func planIsBlindWhenNothingIsDeclared() {
        let plan = SchemeCatalog.plan(candidates: ["x://", "y://"],
                                      declared: [], canOpen: { _ in false })
        #expect(plan == ["x://", "y://"])
    }

    @Test func verifiedGamesCarryTheirHomeScreenStyleName() {
        // The store title is a mouthful; the tile should read like the
        // phone's own home screen.
        #expect(SchemeCatalog.displayName(for: "League of Legends: Wild Rift")
                == "Wild Rift")
        #expect(SchemeCatalog.displayName(for: "Candy Crush Saga") == nil)
    }
}
