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

    @Test func externalAppStringsAreTranslated() {
        #expect(localizedValue("Add a game", language: "zh-Hans") == "添加游戏")
        #expect(localizedValue("Add a game", language: "zh-Hant") == "新增遊戲")
        #expect(localizedValue("Test launch", language: "zh-Hans") == "测试启动")
        #expect(localizedValue("Couldn't open", language: "zh-Hans") == "打不开")
        #expect(localizedValue("Cancel", language: "zh-Hant") == "取消")
        #expect(localizedValue("Add", language: "zh-Hans") == "添加")
        #expect(localizedValue("Opened", language: "zh-Hant") == "已打開")
        #expect(localizedValue("Add this game?", language: "zh-Hans") == "要添加这个游戏吗？")
        #expect(localizedValue("Add this game?", language: "zh-Hant") == "要新增這個遊戲嗎？")
        #expect(localizedValue("Set up link", language: "zh-Hans") == "设置链接")
        #expect(localizedValue("Open App Store", language: "zh-Hant") == "打開 App Store")
        #expect(localizedValue("Opens the App Store every time — link it to launch directly?",
                               language: "zh-Hans") == "每次都会打开 App Store——要设置直接启动的链接吗？")
        #expect(localizedValue("Find launch link", language: "zh-Hans") == "自动查找启动链接")
        #expect(localizedValue("Find launch link", language: "zh-Hant") == "自動尋找啟動連結")
        #expect(localizedValue("Already added", language: "zh-Hans") == "已添加")
        #expect(localizedValue("Already added", language: "zh-Hant") == "已新增")
        #expect(localizedValue("Remove", language: "zh-Hans") == "移除")
        #expect(localizedValue("Edit", language: "zh-Hant") == "編輯")
        #expect(localizedValue("OK", language: "zh-Hans") == "好")
        let schemeFooter = "iOS needs an app's link (URL scheme) to open it directly. "
            + "Without one, the tile opens its App Store page instead."
        #expect(localizedValue(schemeFooter, language: "zh-Hans")
                == "iOS 需要应用的链接（URL Scheme）才能直接打开它。没有链接时，会改为打开它的 App Store 页面。")
        #expect(localizedValue(schemeFooter, language: "zh-Hant")
                == "iOS 需要應用程式的連結（URL Scheme）才能直接開啟它。沒有連結時，會改為開啟它的 App Store 頁面。")
    }

    @Test func springboardStringsAreTranslated() {
        #expect(localizedValue("Home", language: "zh-Hans") == "首页")
        #expect(localizedValue("Home", language: "zh-Hant") == "首頁")
        #expect(localizedValue("Apps", language: "zh-Hans") == "应用")
        #expect(localizedValue("Apps", language: "zh-Hant") == "應用")
        #expect(localizedValue("Done", language: "zh-Hans") == "完成")
        #expect(localizedValue("New collection", language: "zh-Hans") == "新合集")
        #expect(localizedValue("New collection", language: "zh-Hant") == "新合輯")
        #expect(localizedValue("Collection name", language: "zh-Hant") == "合輯名稱")
        #expect(localizedValue("Coming soon", language: "zh-Hans") == "敬请期待")
    }
}
