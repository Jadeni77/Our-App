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
        #expect(localizedValue("Pogo", language: "zh-Hans") == "蹦蹦")
        #expect(localizedValue("Pogo", language: "zh-Hant") == "蹦蹦")
        #expect(localizedValue("Bounce — turn rubbery and ricochet at full speed",
                               language: "zh-Hans") == "弹跳——变得像橡皮，全速反弹")
        #expect(localizedValue("Bounce — turn rubbery and ricochet at full speed",
                               language: "zh-Hant") == "彈跳——變得像橡皮，全速反彈")
        #expect(localizedValue("Prism", language: "zh-Hans") == "棱镜")
        #expect(localizedValue("Prism", language: "zh-Hant") == "稜鏡")
        #expect(localizedValue("Cavern veil", language: "zh-Hans") == "洞窟夜幕")
        #expect(localizedValue("Cavern veil", language: "zh-Hant") == "洞窟夜幕")
        #expect(localizedValue("The helmet shrugs off sky-hits — strike from the side",
                               language: "zh-Hans") == "头盔挡得住天上来的——从侧面打")
        #expect(localizedValue("The helmet shrugs off sky-hits — strike from the side",
                               language: "zh-Hant") == "頭盔擋得住天上來的——從側面打")
        #expect(localizedValue("The Crystal Caverns", language: "zh-Hans") == "水晶洞窟")
        #expect(localizedValue("The Crystal Caverns", language: "zh-Hant") == "水晶洞窟")
        #expect(localizedValue("The caverns echo — bank your shots off the walls",
                               language: "zh-Hans") == "洞窟有回声——借墙壁反弹你的星星")
        #expect(localizedValue("The caverns echo — bank your shots off the walls",
                               language: "zh-Hant") == "洞窟有回聲——借牆壁反彈你的星星")
        #expect(localizedValue("Nebula", language: "zh-Hant") == "星雲")
        #expect(localizedValue("Dawn veil", language: "zh-Hans") == "拂晓纱")
        #expect(localizedValue("Golden slingshot", language: "zh-Hant") == "金彈弓")
        #expect(localizedValue("Reward track", language: "zh-Hans") == "奖励之路")
        #expect(localizedValue("Reward track", language: "zh-Hant") == "獎勵之路")
        #expect(localizedValue("New unlock!", language: "zh-Hans") == "新解锁！")
        #expect(localizedValue("Stardust", language: "zh-Hant") == "星塵")
        #expect(localizedValue("Aurora", language: "zh-Hans") == "极光")
        #expect(localizedValue("Comet", language: "zh-Hans") == "彗星尾迹")
        #expect(localizedValue("Comet", language: "zh-Hant") == "彗星尾跡")
        #expect(localizedValue("Midnight", language: "zh-Hans") == "午夜")
        #expect(localizedValue("Midnight", language: "zh-Hant") == "午夜")
        #expect(localizedValue("Obsidian slingshot", language: "zh-Hans") == "曜石弹弓")
        #expect(localizedValue("Obsidian slingshot", language: "zh-Hant") == "曜石彈弓")
        #expect(localizedValue("A sparkle your star wears in flight", language: "zh-Hans") == "飞行时跟随星星的光尾")
        #expect(localizedValue("A sparkle your star wears in flight", language: "zh-Hant") == "飛行時跟隨星星的光尾")
        #expect(localizedValue("Re-tints the campaign map", language: "zh-Hans") == "给闯关星图换个色调")
        #expect(localizedValue("Re-tints the campaign map", language: "zh-Hant") == "給闖關星圖換個色調")
        #expect(localizedValue("Dresses the slingshot", language: "zh-Hans") == "给弹弓换个模样")
        #expect(localizedValue("Dresses the slingshot", language: "zh-Hant") == "給彈弓換個模樣")
        #expect(localizedValue("On the roadmap", language: "zh-Hans") == "在路上")
        #expect(localizedValue("On the roadmap", language: "zh-Hant") == "在路上")
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
        #expect(localizedValue("The Deep Gloom", language: "zh-Hans") == "幽影深处")
        #expect(localizedValue("The Deep Gloom", language: "zh-Hant") == "幽影深處")
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
        #expect(localizedValue("+%lld moondust", language: "zh-Hans") == "月尘 +%lld")
        #expect(localizedValue("+%lld moondust", language: "zh-Hant") == "月塵 +%lld")
        #expect(localizedValue("Moondust", language: "zh-Hans") == "月尘")
        #expect(localizedValue("Moondust", language: "zh-Hant") == "月塵")
        #expect(localizedValue("What moondust does", language: "zh-Hans") == "月尘是干什么的")
        #expect(localizedValue("What moondust does", language: "zh-Hant") == "月塵是做什麼的")
        #expect(localizedValue("Nox is different — summoning him costs 40 every time.",
                               language: "zh-Hans") == "洞洞不一样——每次召唤都要 40 月尘。")
        #expect(localizedValue("Nox is different — summoning him costs 40 every time.",
                               language: "zh-Hant") == "洞洞不一樣——每次召喚都要 40 月塵。")
        #expect(localizedValue("Summon him from the star picker — 40 moondust a visit",
                               language: "zh-Hans") == "在选星面板召唤他——每次 40 月尘")
        #expect(localizedValue("Summon him from the star picker — 40 moondust a visit",
                               language: "zh-Hant") == "在選星面板召喚他——每次 40 月塵")
        #expect(localizedValue("Buys star switches mid-level", language: "zh-Hans") == "用来在关卡里换星星上场")
        #expect(localizedValue("Buys star switches mid-level", language: "zh-Hant") == "用來在關卡裡換星星上場")
        #expect(localizedValue("Smashing pieces earns moondust — tougher pieces pay more. First clears add +20.",
                               language: "zh-Hans") == "通关时，拆掉的部件都会换成月尘——越硬的部件给得越多。首次通关再加 20。")
        #expect(localizedValue("Spend it mid-level: tap your star's name chip to switch who flies. The first switch is free; repeats cost 25.",
                               language: "zh-Hant") == "在關卡裡花掉它：點星星名字的小牌子換人上場。每關第一次免費，之後每次 25。")
        #expect(localizedValue("Choose your star", language: "zh-Hans") == "选一颗星上场")
        #expect(localizedValue("Choose your star", language: "zh-Hant") == "選一顆星上場")
        #expect(localizedValue("Free", language: "zh-Hans") == "免费")
        #expect(localizedValue("Free", language: "zh-Hant") == "免費")
        #expect(localizedValue("Paused", language: "zh-Hans") == "已暂停")
        #expect(localizedValue("Paused", language: "zh-Hant") == "已暫停")
        #expect(localizedValue("Resume", language: "zh-Hans") == "继续游戏")
        #expect(localizedValue("Resume", language: "zh-Hant") == "繼續遊戲")
        #expect(localizedValue("Replay level", language: "zh-Hans") == "重玩本关")
        #expect(localizedValue("Replay level", language: "zh-Hant") == "重玩本關")
        #expect(localizedValue("Back to home", language: "zh-Hans") == "回到主页")
        #expect(localizedValue("Back to home", language: "zh-Hant") == "回到主頁")
        #expect(localizedValue("Exit game", language: "zh-Hans") == "退出游戏")
        #expect(localizedValue("Exit game", language: "zh-Hant") == "退出遊戲")
        #expect(localizedValue("Menu", language: "zh-Hans") == "菜单")
        #expect(localizedValue("Menu", language: "zh-Hant") == "選單")
        #expect(localizedValue("Cloudfoam bounces you — aim off the pads",
                               language: "zh-Hans") == "云绵会把你弹起来——借垫子瞄准")
        #expect(localizedValue("Wind bends every arc — trust your read, not the dots",
                               language: "zh-Hant") == "風會吹彎每道弧線——別全信虛線")
        #expect(localizedValue("The deep glooms fight back — watch their tricks",
                               language: "zh-Hans") == "深处的阴影会反击——看清它们的招")
        #expect(localizedValue("The deep glooms fight back — watch their tricks",
                               language: "zh-Hant") == "深處的陰影會反擊——看清它們的招")
        #expect(localizedValue("Back", language: "zh-Hans") == "返回")
        #expect(localizedValue("Back", language: "zh-Hant") == "返回")
        #expect(localizedValue("Abilities", language: "zh-Hans") == "技能图鉴")
        #expect(localizedValue("Abilities", language: "zh-Hant") == "技能圖鑑")
        #expect(localizedValue("%lld★ to go", language: "zh-Hans") == "还差 %lld★")
        #expect(localizedValue("+%lld★", language: "zh-Hant") == "+%lld★")
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
        #expect(localizedValue("Continue", language: "zh-Hans") == "继续")
        #expect(localizedValue("Continue", language: "zh-Hant") == "繼續")
        #expect(localizedValue("All clear — replay your sky", language: "zh-Hans")
                == "全部通关——回去重温星空吧")
        #expect(localizedValue("Co-op & 1v1 — on the roadmap", language: "zh-Hant")
                == "雙人合作與對決——都在路上")
        #expect(localizedValue("The glooms giggle. Try again?", language: "zh-Hans")
                == "阴影们在偷笑。再来一次？")
        #expect(localizedValue("W%lld · L%lld", language: "zh-Hant") == "W%lld · L%lld")
        #expect(localizedValue("Its shell breaks first — hit it twice", language: "zh-Hans")
                == "它有壳——先敲碎，再打一下")
        #expect(localizedValue("It jumps when you land close — bait it", language: "zh-Hant")
                == "你落得近它就跳——先騙它跳")
        #expect(localizedValue("Only a power can touch the mist", language: "zh-Hans")
                == "只有技能碰得到雾")
        #expect(localizedValue("The Great Gloom shrugs — chip away", language: "zh-Hant")
                == "巨影不怕撞——慢慢磨")
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
