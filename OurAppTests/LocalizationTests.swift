import Foundation
import Testing
@testable import OurApp

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

    @Test func versionFooterKeyShipsInAllLanguages() {
        // The brand + version line is locale-invariant, but it still goes
        // through the catalog (P5) — pin the key so it can't silently drop.
        #expect(localizedValue("OurApp %@", language: "en") == "OurApp %@")
        #expect(localizedValue("OurApp %@", language: "zh-Hans") == "OurApp %@")
        #expect(localizedValue("OurApp %@", language: "zh-Hant") == "OurApp %@")
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
        #expect(localizedValue("Use a Shortcut instead", language: "zh-Hans") == "改用快捷指令")
        #expect(localizedValue("Use a Shortcut instead", language: "zh-Hant") == "改用捷徑")
        #expect(localizedValue("Open Shortcuts", language: "zh-Hant") == "打開捷徑")
        #expect(localizedValue("Copy name", language: "zh-Hans") == "复制名称")
        #expect(localizedValue("Set up link", language: "zh-Hans") == "设置链接")
        #expect(localizedValue("Open App Store", language: "zh-Hant") == "打開 App Store")
        #expect(localizedValue("Opens the App Store every time — link it to launch directly?",
                               language: "zh-Hans") == "每次都会打开 App Store——要设置直接启动的链接吗？")
        #expect(localizedValue("Find launch link", language: "zh-Hans") == "自动查找启动链接")
        #expect(localizedValue("Find launch link", language: "zh-Hant") == "自動尋找啟動連結")
        #expect(localizedValue("Already added — edit it", language: "zh-Hans") == "已添加——去编辑")
        #expect(localizedValue("Already added — edit it", language: "zh-Hant") == "已新增——去編輯")
        #expect(localizedValue("Remove", language: "zh-Hans") == "移除")
        #expect(localizedValue("Do you want to remove “%@”?", language: "zh-Hans")
                == "要移除“%@”吗？")
        #expect(localizedValue("Do you want to remove “%@”?", language: "zh-Hant")
                == "要移除「%@」嗎？")
        #expect(localizedValue("Edit", language: "zh-Hant") == "編輯")
        #expect(localizedValue("OK", language: "zh-Hans") == "好")
        let schemeFooter = "iOS needs an app's link (URL scheme) to open it directly. "
            + "Without one, the tile opens its App Store page instead."
        #expect(localizedValue(schemeFooter, language: "zh-Hans")
                == "iOS 需要应用的链接（URL Scheme）才能直接打开它。没有链接时，会改为打开它的 App Store 页面。")
        #expect(localizedValue(schemeFooter, language: "zh-Hant")
                == "iOS 需要應用程式的連結（URL Scheme）才能直接開啟它。沒有連結時，會改為開啟它的 App Store 頁面。")
    }

    @Test func currentBundleFollowsTheInAppOverrideImmediately() throws {
        // String(localized:) follows AppleLanguages, which realigns only at
        // the next launch — AppLanguage.currentBundle is how mid-session
        // lookups agree with the on-screen language (post-#14 follow-up).
        // A private suite, never the standard domain: suites run in parallel
        // and a shared-default write would race every other lookup.
        let suite = "localization-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(AppLanguage.simplifiedChinese.rawValue,
                     forKey: AppLanguage.storageKey)
        // The production call form, deliberately: String(localized:bundle:)
        // resolves via the bundle's preferred localization (it ignores any
        // locale hint), so the single-lproj bundle IS the mechanism — pin it.
        #expect(String(localized: "New collection",
                       bundle: AppLanguage.currentBundle(defaults)) == "新合集")

        defaults.set(AppLanguage.system.rawValue, forKey: AppLanguage.storageKey)
        #expect(AppLanguage.currentBundle(defaults) == .main)
    }

    @Test func moonshotShellStringsAreTranslated() {
        #expect(localizedValue("Moonshot", language: "zh-Hans") == "奔月")
        #expect(localizedValue("Moonshot", language: "zh-Hant") == "奔月")
        #expect(localizedValue("Campaign", language: "zh-Hans") == "闯关")
        #expect(localizedValue("Campaign", language: "zh-Hant") == "闖關")
        #expect(localizedValue("Co-op", language: "zh-Hans") == "双人合作")
        #expect(localizedValue("1v1", language: "zh-Hant") == "對決")
        #expect(localizedValue("Relight our sky", language: "zh-Hans") == "点亮我们的星空")
        #expect(localizedValue("Level %lld", language: "zh-Hant") == "第 %lld 關")
        #expect(localizedValue("Fling %lld", language: "zh-Hans") == "第 %lld 发")
        #expect(localizedValue("Par %lld", language: "zh-Hant") == "標準 %lld 發")
        #expect(localizedValue("Next level", language: "zh-Hans") == "下一关")
        #expect(localizedValue("Replay", language: "zh-Hant") == "重玩")
        #expect(localizedValue("Try again", language: "zh-Hans") == "再试一次")
        #expect(localizedValue("%lld stars", language: "zh-Hant") == "%lld 顆星")
        #expect(localizedValue("Mochi", language: "zh-Hans") == "团团")
        #expect(localizedValue("Mochi", language: "zh-Hant") == "團團")
        #expect(localizedValue("Zip", language: "zh-Hans") == "嗖嗖")
        #expect(localizedValue("Twinkle", language: "zh-Hant") == "雙雙")
        #expect(localizedValue("Nox", language: "zh-Hans") == "洞洞")
        #expect(localizedValue("Misty", language: "zh-Hans") == "雾雾")
        #expect(localizedValue("Misty", language: "zh-Hant") == "霧霧")
        #expect(localizedValue("Nebula", language: "zh-Hant") == "星雲")
        #expect(localizedValue("Dawn veil", language: "zh-Hans") == "拂晓纱")
        #expect(localizedValue("Golden slingshot", language: "zh-Hant") == "金彈弓")
        #expect(localizedValue("Reward track", language: "zh-Hans") == "奖励之路")
        #expect(localizedValue("Reward track", language: "zh-Hant") == "獎勵之路")
        #expect(localizedValue("New unlock!", language: "zh-Hans") == "新解锁！")
        #expect(localizedValue("Stardust", language: "zh-Hant") == "星塵")
        #expect(localizedValue("Aurora", language: "zh-Hans") == "极光")
        #expect(localizedValue("Play as %@", language: "zh-Hant") == "讓 %@ 上場")
        #expect(localizedValue("Level %lld, locked", language: "zh-Hans") == "第 %lld 关，未解锁")
        #expect(localizedValue("Music", language: "zh-Hans") == "音乐")
        #expect(localizedValue("Music", language: "zh-Hant") == "音樂")
        #expect(localizedValue("On", language: "zh-Hans") == "开")
        #expect(localizedValue("Off", language: "zh-Hant") == "關")
        #expect(localizedValue("Level failed", language: "zh-Hans") == "挑战失败")
        #expect(localizedValue("Not equipped", language: "zh-Hant") == "未裝備")
        #expect(localizedValue("Equipped", language: "zh-Hans") == "已装备")
        #expect(localizedValue("Every star either of us earns lights this up",
                               language: "zh-Hans") == "我们俩赢得的每颗星都会点亮这里")
        #expect(localizedValue("The Moonlit Fields", language: "zh-Hans") == "月光原野")
        #expect(localizedValue("The Moonlit Fields", language: "zh-Hant") == "月光原野")
        #expect(localizedValue("The Cloudfoam Skies", language: "zh-Hans") == "云绵天空")
        #expect(localizedValue("The Cloudfoam Skies", language: "zh-Hant") == "雲綿天空")
        #expect(localizedValue("The Storm Heights", language: "zh-Hans") == "风暴之巅")
        #expect(localizedValue("The Storm Heights", language: "zh-Hant") == "風暴之巔")
        #expect(localizedValue("One fling", language: "zh-Hans") == "一发通关")
        #expect(localizedValue("One fling", language: "zh-Hant") == "一發通關")
        #expect(localizedValue("No ability", language: "zh-Hans") == "未用技能")
        #expect(localizedValue("No ability", language: "zh-Hant") == "未用技能")
        #expect(localizedValue("Clean sweep", language: "zh-Hans") == "全部拆光")
        #expect(localizedValue("Clean sweep", language: "zh-Hant") == "全部拆光")
        #expect(localizedValue("Pop every gloom to relight the sky", language: "zh-Hans")
                == "打走所有阴影，点亮我们的星空")
        #expect(localizedValue("Pop every gloom to relight the sky", language: "zh-Hant")
                == "打走所有陰影，點亮我們的星空")
        #expect(localizedValue("Tap — %@'s power!", language: "zh-Hans") == "点一下——%@的技能！")
        #expect(localizedValue("Tap — %@'s power!", language: "zh-Hant") == "點一下——%@的技能！")
        #expect(localizedValue("Moon Slam — stop mid-air and drop like the moon",
                               language: "zh-Hans") == "月落——空中急停，垂直砸下")
        #expect(localizedValue("Comet Dash — a burst of speed, ×2 vs crystal and wood",
                               language: "zh-Hant") == "彗星衝刺——瞬間加速，對水晶和月木傷害×2")
        #expect(localizedValue("Split — one star becomes two", language: "zh-Hans") == "一分为二——一颗星变成两颗")
        #expect(localizedValue("Gravity Well — freeze and pull the world in",
                               language: "zh-Hant") == "引力井——凝住自己，把世界拉過來")
        #expect(localizedValue("Phase — turn to mist, slip through one piece",
                               language: "zh-Hans") == "雾化——化作薄雾，穿过一块积木")
        #expect(localizedValue("Tap mid-flight to use it", language: "zh-Hant") == "飛行途中點一下就能用")
        #expect(localizedValue("Let's go", language: "zh-Hans") == "出发！")
        #expect(localizedValue("Unlocks at %lld★", language: "zh-Hant") == "集滿 %lld★ 解鎖")
        #expect(localizedValue("Cloudfoam bounces you — aim off the pads",
                               language: "zh-Hans") == "云绵会把你弹起来——借垫子瞄准")
        #expect(localizedValue("Wind bends every arc — trust your read, not the dots",
                               language: "zh-Hant") == "風會吹彎每道弧線——別全信虛線")
        #expect(localizedValue("%lld★ to go", language: "zh-Hans") == "还差 %lld★")
        #expect(localizedValue("At or under par — 3 stars", language: "zh-Hant") == "打平或低於標準桿——3星")
        #expect(localizedValue("One over par — 2 stars", language: "zh-Hans") == "超出标准杆一发——2星")
        #expect(localizedValue("Cleared — 1 star", language: "zh-Hant") == "通關——1星")
        #expect(localizedValue("How stars work", language: "zh-Hans") == "星星是怎么来的")
        #expect(localizedValue("Clear a level — 1★. One over par — 2★. At or under par — 3★.",
                               language: "zh-Hant") == "通關得 1★。超出標準桿一發得 2★。打平或更少得 3★。")
        #expect(localizedValue("Both partners' best runs pool together — solo and co-op.",
                               language: "zh-Hans") == "我们俩各自的最好成绩会汇在一起——单人和合作都算。")
        #expect(localizedValue("Milestones unlock characters, trails, and looks.",
                               language: "zh-Hant") == "攢到里程碑就解鎖新角色、拖尾和外觀。")
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
        #expect(localizedValue("Page %lld of %lld", language: "zh-Hans")
                == "第 %1$lld 页，共 %2$lld 页")
        #expect(localizedValue("Page %lld of %lld", language: "zh-Hant")
                == "第 %1$lld 頁，共 %2$lld 頁")
    }
}
