import Foundation

/// A cuisine as localized DATA (decision F6): a stable id for history, display
/// names in all our languages, and the multi-language `searchTerms` the
/// restaurant provider queries with (decision F7). "火锅" IS the cuisine, not a
/// translation of it.
struct Cuisine: Equatable, Hashable {
    let id: String
    let emoji: String
    let namesByLanguage: [String: String]
    let searchTerms: [String]

    /// Display name in the app's active language (String Catalog languages).
    var displayName: String {
        name(for: Bundle.main.preferredLocalizations.first ?? "en")
    }

    /// Deterministic resolution for tests: exact language → English → id.
    func name(for language: String) -> String {
        namesByLanguage[language] ?? namesByLanguage["en"] ?? id
    }

    /// View-layer resolution that follows the \.locale environment, so the
    /// in-app language override (P9) switches cuisine names live. A bare
    /// "zh" carries no script — the maximal identifier supplies Hans/Hant.
    func name(for locale: Locale) -> String {
        guard locale.language.languageCode?.identifier == "zh" else {
            return name(for: locale.language.languageCode?.identifier ?? "en")
        }
        let maximal = locale.language.maximalIdentifier
        return name(for: maximal.contains("Hant") ? "zh-Hant" : "zh-Hans")
    }

    var isCustom: Bool { id.hasPrefix("custom:") }

    /// A free-form typed cuisine: the typed text is the name in every language
    /// and the only search term. Fallback fork-and-knife emoji.
    static func custom(_ text: String) -> Cuisine {
        Cuisine(
            id: "custom:\(text.lowercased())",
            emoji: "🍽️",
            namesByLanguage: ["en": text, "zh-Hans": text, "zh-Hant": text],
            searchTerms: [text]
        )
    }
}

/// The built-in pool — still the one editable place (F6 shape).
/// Search terms lead with the Chinese query because that's the harder side to
/// get results for; ordering per region happens in the provider (Task 4).
enum CuisinePool {
    static let all: [Cuisine] = [
        Cuisine(id: "hotpot", emoji: "🍲",
                namesByLanguage: ["en": "Hotpot", "zh-Hans": "火锅", "zh-Hant": "火鍋"],
                searchTerms: ["火锅", "hotpot", "麻辣火锅", "火鍋"]),
        Cuisine(id: "sichuan", emoji: "🌶️",
                namesByLanguage: ["en": "Sichuan", "zh-Hans": "川菜", "zh-Hant": "川菜"],
                searchTerms: ["川菜", "Sichuan food", "四川菜"]),
        Cuisine(id: "cantonese", emoji: "🦆",
                namesByLanguage: ["en": "Cantonese", "zh-Hans": "粤菜", "zh-Hant": "粵菜"],
                searchTerms: ["粤菜", "Cantonese food", "粵菜", "广东菜"]),
        Cuisine(id: "dim-sum", emoji: "🥟",
                namesByLanguage: ["en": "Dim Sum", "zh-Hans": "点心", "zh-Hant": "點心"],
                searchTerms: ["点心", "dim sum", "早茶", "點心"]),
        Cuisine(id: "dumplings", emoji: "🥟",
                namesByLanguage: ["en": "Dumplings", "zh-Hans": "饺子", "zh-Hant": "餃子"],
                searchTerms: ["饺子", "dumplings", "餃子"]),
        Cuisine(id: "malatang", emoji: "🍢",
                namesByLanguage: ["en": "Malatang", "zh-Hans": "麻辣烫", "zh-Hant": "麻辣燙"],
                searchTerms: ["麻辣烫", "malatang", "麻辣燙"]),
        Cuisine(id: "hand-pulled-noodles", emoji: "🍜",
                namesByLanguage: ["en": "Hand-pulled Noodles", "zh-Hans": "拉面", "zh-Hant": "拉麵"],
                searchTerms: ["兰州拉面", "hand pulled noodles", "拉面", "拉麵"]),
        Cuisine(id: "congee", emoji: "🥣",
                namesByLanguage: ["en": "Congee", "zh-Hans": "粥", "zh-Hant": "粥"],
                searchTerms: ["粥", "congee", "砂锅粥"]),
        Cuisine(id: "taiwanese", emoji: "🍱",
                namesByLanguage: ["en": "Taiwanese", "zh-Hans": "台湾菜", "zh-Hant": "台灣菜"],
                searchTerms: ["台湾菜", "Taiwanese food", "台灣菜", "卤肉饭"]),
        Cuisine(id: "ramen", emoji: "🍜",
                namesByLanguage: ["en": "Ramen", "zh-Hans": "日式拉面", "zh-Hant": "日式拉麵"],
                searchTerms: ["ramen", "日式拉面", "豚骨拉面", "日式拉麵"]),
        Cuisine(id: "sushi", emoji: "🍣",
                namesByLanguage: ["en": "Sushi", "zh-Hans": "寿司", "zh-Hant": "壽司"],
                searchTerms: ["寿司", "sushi", "壽司"]),
        Cuisine(id: "udon", emoji: "🍜",
                namesByLanguage: ["en": "Udon", "zh-Hans": "乌冬面", "zh-Hant": "烏龍麵"],
                searchTerms: ["乌冬面", "udon", "烏龍麵"]),
        Cuisine(id: "tonkatsu", emoji: "🍱",
                namesByLanguage: ["en": "Tonkatsu", "zh-Hans": "日式炸猪排", "zh-Hant": "日式炸豬排"],
                searchTerms: ["炸猪排", "tonkatsu", "日式炸豬排"]),
        Cuisine(id: "japanese-curry", emoji: "🍛",
                namesByLanguage: ["en": "Japanese Curry", "zh-Hans": "日式咖喱", "zh-Hant": "日式咖哩"],
                searchTerms: ["日式咖喱", "japanese curry", "咖喱饭", "日式咖哩"]),
        Cuisine(id: "izakaya", emoji: "🍶",
                namesByLanguage: ["en": "Izakaya", "zh-Hans": "居酒屋", "zh-Hant": "居酒屋"],
                searchTerms: ["居酒屋", "izakaya"]),
        Cuisine(id: "korean-bbq", emoji: "🥩",
                namesByLanguage: ["en": "Korean BBQ", "zh-Hans": "韩式烤肉", "zh-Hant": "韓式烤肉"],
                searchTerms: ["韩式烤肉", "korean bbq", "韓式烤肉"]),
        Cuisine(id: "bibimbap", emoji: "🍚",
                namesByLanguage: ["en": "Bibimbap", "zh-Hans": "石锅拌饭", "zh-Hant": "石鍋拌飯"],
                searchTerms: ["石锅拌饭", "bibimbap", "石鍋拌飯"]),
        Cuisine(id: "korean-fried-chicken", emoji: "🍗",
                namesByLanguage: ["en": "Korean Fried Chicken", "zh-Hans": "韩式炸鸡", "zh-Hant": "韓式炸雞"],
                searchTerms: ["韩式炸鸡", "korean fried chicken", "韓式炸雞"]),
        Cuisine(id: "pho", emoji: "🍜",
                namesByLanguage: ["en": "Pho", "zh-Hans": "越南河粉", "zh-Hant": "越南河粉"],
                searchTerms: ["越南河粉", "pho", "河粉"]),
        Cuisine(id: "banh-mi", emoji: "🥖",
                namesByLanguage: ["en": "Banh Mi", "zh-Hans": "越南法包", "zh-Hant": "越南法包"],
                searchTerms: ["banh mi", "越南三明治", "越南法包"]),
        Cuisine(id: "thai", emoji: "🍛",
                namesByLanguage: ["en": "Thai", "zh-Hans": "泰国菜", "zh-Hant": "泰國菜"],
                searchTerms: ["泰国菜", "thai food", "泰國菜"]),
        Cuisine(id: "indian", emoji: "🍛",
                namesByLanguage: ["en": "Indian", "zh-Hans": "印度菜", "zh-Hant": "印度菜"],
                searchTerms: ["印度菜", "indian food", "咖喱"]),
        Cuisine(id: "pizza", emoji: "🍕",
                namesByLanguage: ["en": "Pizza", "zh-Hans": "披萨", "zh-Hant": "披薩"],
                searchTerms: ["披萨", "pizza", "披薩"]),
        Cuisine(id: "pasta", emoji: "🍝",
                namesByLanguage: ["en": "Pasta", "zh-Hans": "意面", "zh-Hant": "義大利麵"],
                searchTerms: ["意面", "pasta", "意大利面", "義大利麵"]),
        Cuisine(id: "burgers", emoji: "🍔",
                namesByLanguage: ["en": "Burgers", "zh-Hans": "汉堡", "zh-Hant": "漢堡"],
                searchTerms: ["汉堡", "burgers", "漢堡"]),
        Cuisine(id: "sandwiches", emoji: "🥪",
                namesByLanguage: ["en": "Sandwiches", "zh-Hans": "三明治", "zh-Hant": "三明治"],
                searchTerms: ["三明治", "sandwiches"]),
        Cuisine(id: "fried-chicken", emoji: "🍗",
                namesByLanguage: ["en": "Fried Chicken", "zh-Hans": "炸鸡", "zh-Hant": "炸雞"],
                searchTerms: ["炸鸡", "fried chicken", "炸雞"]),
        Cuisine(id: "american-bbq", emoji: "🍖",
                namesByLanguage: ["en": "American BBQ", "zh-Hans": "美式烧烤", "zh-Hant": "美式燒烤"],
                searchTerms: ["美式烧烤", "bbq", "美式燒烤"]),
        Cuisine(id: "steakhouse", emoji: "🥩",
                namesByLanguage: ["en": "Steakhouse", "zh-Hans": "牛排", "zh-Hant": "牛排"],
                searchTerms: ["牛排", "steakhouse", "牛排馆"]),
        Cuisine(id: "seafood", emoji: "🦞",
                namesByLanguage: ["en": "Seafood", "zh-Hans": "海鲜", "zh-Hant": "海鮮"],
                searchTerms: ["海鲜", "seafood", "海鮮"]),
        Cuisine(id: "lobster-roll", emoji: "🦞",
                namesByLanguage: ["en": "Lobster Roll", "zh-Hans": "龙虾卷", "zh-Hant": "龍蝦卷"],
                searchTerms: ["lobster roll", "龙虾卷", "龍蝦卷"]),
        Cuisine(id: "tacos", emoji: "🌮",
                namesByLanguage: ["en": "Tacos", "zh-Hans": "塔可", "zh-Hant": "塔可"],
                searchTerms: ["tacos", "墨西哥菜", "塔可"]),
        Cuisine(id: "burritos", emoji: "🌯",
                namesByLanguage: ["en": "Burritos", "zh-Hans": "墨西哥卷饼", "zh-Hant": "墨西哥捲餅"],
                searchTerms: ["burritos", "墨西哥卷饼", "墨西哥捲餅"]),
        Cuisine(id: "shawarma", emoji: "🌯",
                namesByLanguage: ["en": "Shawarma", "zh-Hans": "沙威玛", "zh-Hant": "沙威瑪"],
                searchTerms: ["shawarma", "沙威玛", "中东烤肉"]),
        Cuisine(id: "falafel", emoji: "🧆",
                namesByLanguage: ["en": "Falafel", "zh-Hans": "法拉费", "zh-Hant": "法拉費"],
                searchTerms: ["falafel", "中东菜"]),
        Cuisine(id: "mediterranean", emoji: "🥙",
                namesByLanguage: ["en": "Mediterranean", "zh-Hans": "地中海菜", "zh-Hant": "地中海菜"],
                searchTerms: ["地中海菜", "mediterranean food"]),
        Cuisine(id: "greek", emoji: "🥗",
                namesByLanguage: ["en": "Greek", "zh-Hans": "希腊菜", "zh-Hant": "希臘菜"],
                searchTerms: ["希腊菜", "greek food", "希臘菜"]),
        Cuisine(id: "poke", emoji: "🥗",
                namesByLanguage: ["en": "Poke", "zh-Hans": "夏威夷拌饭", "zh-Hant": "夏威夷拌飯"],
                searchTerms: ["poke bowl", "夏威夷拌饭", "poke"]),
        Cuisine(id: "brunch", emoji: "🥞",
                namesByLanguage: ["en": "Brunch", "zh-Hans": "早午餐", "zh-Hant": "早午餐"],
                searchTerms: ["早午餐", "brunch"]),
    ]

    /// Purely random (v1 resolution stands); excluding the current proposal
    /// keeps a re-roll from repeating itself.
    static func draw(excluding excluded: Cuisine? = nil) -> Cuisine {
        let candidates = all.filter { $0 != excluded }
        return candidates.randomElement() ?? all[0]
    }

    /// Manual-entry resolution across every language and search term (v2 scope):
    /// typing 火锅, Hotpot, or 麻辣火锅 all land on the same pool entry.
    static func match(_ text: String) -> Cuisine? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return all.first { cuisine in
            cuisine.namesByLanguage.values.contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
                || cuisine.searchTerms.contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        }
    }
}
