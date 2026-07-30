import Foundation
import Testing

struct LocalizationTests {
    private func localizedValue(_ key: String, language: String) -> String? {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return nil }
        let value = bundle.localizedString(forKey: key, value: "«missing»", table: nil)
        return value == "«missing»" ? nil : value
    }

    @Test func appShipsAllThreeLanguages() {
        for language in ["en", "zh-Hans", "zh-Hant"] {
            #expect(Bundle.main.path(forResource: language, ofType: "lproj") != nil,
                    "missing \(language).lproj")
        }
    }

    @Test func shellStringsAreTranslated() {
        #expect(localizedValue("Set your anniversary", language: "zh-Hans") == "设置纪念日")
        #expect(localizedValue("Set your anniversary", language: "zh-Hant") == "設定紀念日")
        #expect(localizedValue("Our space", language: "zh-Hans") == "我们的空间")
        #expect(localizedValue("What should we eat?", language: "zh-Hant") == "吃點什麼好？")
    }

    @Test func languagePickerStringsAreTranslated() {
        #expect(localizedValue("Language", language: "zh-Hans") == "语言")
        #expect(localizedValue("Language", language: "zh-Hant") == "語言")
        #expect(localizedValue("System", language: "zh-Hans") == "跟随系统")
        #expect(localizedValue("System", language: "zh-Hant") == "跟隨系統")
    }

    @Test func counterHeroStringsAreTranslated() {
        #expect(localizedValue("We've been together for", language: "zh-Hans") == "我们在一起已经")
        #expect(localizedValue("We've been together for", language: "zh-Hant") == "我們在一起已經")
        #expect(localizedValue("day", language: "zh-Hans") == "天")
        #expect(localizedValue("days", language: "zh-Hant") == "天")
    }

    @Test func foodModuleStringsAreTranslated() {
        #expect(localizedValue("Agree", language: "zh-Hans") == "同意")
        #expect(localizedValue("Re-roll", language: "zh-Hant") == "換一個")
        #expect(localizedValue("Find places near us", language: "zh-Hans") == "找找附近的店")
        #expect(localizedValue("Unnamed spot", language: "zh-Hant") == "無名小店")
    }

    @Test func springboardStringsAreTranslated() {
        #expect(localizedValue("Home", language: "zh-Hans") == "首页")
        #expect(localizedValue("Home", language: "zh-Hant") == "首頁")
        #expect(localizedValue("Games", language: "zh-Hans") == "游戏")
        #expect(localizedValue("Games", language: "zh-Hant") == "遊戲")
        #expect(localizedValue("Done", language: "zh-Hans") == "完成")
        #expect(localizedValue("New collection", language: "zh-Hans") == "新合集")
        #expect(localizedValue("New collection", language: "zh-Hant") == "新合輯")
        #expect(localizedValue("Collection name", language: "zh-Hant") == "合輯名稱")
        #expect(localizedValue("Coming soon", language: "zh-Hans") == "敬请期待")
    }
}
