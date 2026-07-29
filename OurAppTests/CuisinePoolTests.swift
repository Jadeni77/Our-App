import Testing
@testable import OurApp

struct CuisinePoolTests {
    @Test func poolHasThirtyToFortyEntriesWithUniqueIDs() {
        #expect(CuisinePool.all.count >= 30)
        #expect(CuisinePool.all.count <= 40)
        #expect(Set(CuisinePool.all.map(\.id)).count == CuisinePool.all.count)
    }

    @Test func everyEntryCarriesAllThreeLanguagesAndSearchTerms() {
        for cuisine in CuisinePool.all {
            for language in ["en", "zh-Hans", "zh-Hant"] {
                #expect(cuisine.namesByLanguage[language]?.isEmpty == false,
                        "\(cuisine.id) missing \(language)")
            }
            #expect(cuisine.searchTerms.count >= 2, "\(cuisine.id) needs ≥2 search terms")
        }
    }

    @Test func nameFallsBackToEnglishThenID() {
        let hotpot = CuisinePool.all.first { $0.id == "hotpot" }!
        #expect(hotpot.name(for: "zh-Hans") == "火锅")
        #expect(hotpot.name(for: "zh-Hant") == "火鍋")
        #expect(hotpot.name(for: "fr") == "Hotpot") // unknown language → English
        let bare = Cuisine(id: "mystery", emoji: "❓", namesByLanguage: [:], searchTerms: ["x", "y"])
        #expect(bare.name(for: "en") == "mystery") // no names at all → id
    }

    @Test func drawReturnsAPoolMemberAndHonorsExclusion() {
        #expect(CuisinePool.all.contains(CuisinePool.draw()))
        let excluded = CuisinePool.all[0]
        for _ in 0..<200 {
            #expect(CuisinePool.draw(excluding: excluded) != excluded)
        }
    }

    @Test func matchResolvesAcrossLanguagesAndTerms() {
        #expect(CuisinePool.match("hotpot")?.id == "hotpot")      // en name
        #expect(CuisinePool.match("火锅")?.id == "hotpot")         // zh-Hans name
        #expect(CuisinePool.match("火鍋")?.id == "hotpot")         // zh-Hant name
        #expect(CuisinePool.match("麻辣火锅")?.id == "hotpot")      // search term
        #expect(CuisinePool.match("  RAMEN ")?.id == "ramen")     // trim + case
        #expect(CuisinePool.match("plasma jelly") == nil)
    }

    @Test func customCuisineKeepsTypedTextEverywhere() {
        let typed = Cuisine.custom("Xinjiang BBQ")
        #expect(typed.isCustom)
        #expect(typed.displayName == "Xinjiang BBQ")
        #expect(typed.searchTerms == ["Xinjiang BBQ"])
        #expect(typed.emoji == "🍽️")
    }
}
