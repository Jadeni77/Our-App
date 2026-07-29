# Food Decision v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Localize the food-decision module end-to-end (en / zh-Hans / zh-Hant) with a localized cuisine data pool, make restaurant search Chinese-capable via per-cuisine `searchTerms` + region-aware querying (F6/F7), and dress the module in the platform theme — build order items 7–10 of `docs/modules/food-decision.md`.

**Architecture:** `Cuisine` becomes localized data (stable `id`, per-language names, `searchTerms`); the pool carries all three languages. `DecisionRecord` gains an optional `cuisineID` (additive SwiftData migration). `RestaurantProvider` now takes the whole `Cuisine` — the multi-term, region-ordered, merge/dedupe strategy stays internal to the MapKit implementation (UI untouched, per the doc). Views swap hardcoded strings for catalog keys and adopt `Theme`/glass.

**Tech Stack:** SwiftUI, SwiftData, MapKit, CoreLocation (CLGeocoder for region), String Catalog, Swift Testing.

## Global Constraints

- Working directory `/Users/meixiaobin/Desktop/Our-App`, branch `food-decision-v2`.
- iOS deployment target 17.0. Build/test on the **iPhone 17 Pro** simulator, Xcode 26.2.
- $0 rule: no packages, no paid APIs. `placemark`-API deprecation warnings under the iOS 26 SDK remain plan-accepted.
- Synchronized folder groups: **never edit `project.pbxproj`**.
- **Every user-facing string** must be a String Catalog key with en, zh-Hans, and zh-Hant values. Chinese strings in this plan are copied character-for-character.
- Module contract: module code stays under `OurApp/Modules/FoodDecision/`; it consumes core `Theme`/`glassCard`/`Haptics` tokens but never touches shell internals.
- Existing v1 `DecisionRecord` rows must stay readable — schema changes are **additive only** (optional new property).
- Open-question resolutions adopted (doc leans, finalized here): **sequential term querying with early exit at the cap (8)**; **region fit from the search location (reverse-geocoded country), device locale as fallback**.
- Commit messages: plain imperative English, **NO AI attribution of any kind**.
- Full suite: `xcodebuild test -project OurApp.xcodeproj -scheme OurApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet` (up to 10 min; `-only-testing:OurAppTests/<Suite>` for TDD loops). Baseline entering this plan: 32 tests / 9 suites green.

---

### Task 1: Localized Cuisine model + data pool (TDD)

**Files:**
- Modify: `OurApp/Modules/FoodDecision/CuisinePool.swift` (full rewrite below)
- Test: `OurAppTests/CuisinePoolTests.swift` (full rewrite below)

**Interfaces:**
- Consumes: nothing new.
- Produces (every later task uses these verbatim):
  ```swift
  struct Cuisine: Equatable, Hashable {
      let id: String                       // stable slug, never shown
      let emoji: String
      let namesByLanguage: [String: String] // keys: "en", "zh-Hans", "zh-Hant"
      let searchTerms: [String]            // mixed-language MKLocalSearch queries
      var displayName: String              // resolves via Bundle.main.preferredLocalizations
      func name(for language: String) -> String  // en fallback, then id
      static func custom(_ text: String) -> Cuisine
      var isCustom: Bool                   // id starts with "custom:"
  }
  enum CuisinePool {
      static let all: [Cuisine]
      static func draw(excluding: Cuisine? = nil) -> Cuisine
      static func match(_ text: String) -> Cuisine?  // case-insensitive across ALL names + searchTerms
  }
  ```
  Note: v1's `Cuisine(name:emoji:)` disappears. Tasks 2–6 update every consumer; the compiler is the checklist.

- [ ] **Step 1: Rewrite the test file `OurAppTests/CuisinePoolTests.swift`**

```swift
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test ... -only-testing:OurAppTests/CuisinePoolTests -quiet`
Expected: FAIL — compile errors (`namesByLanguage`, `match`, `custom` don't exist).

- [ ] **Step 3: Rewrite `OurApp/Modules/FoodDecision/CuisinePool.swift`**

```swift
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
```

- [ ] **Step 4: Run to verify the new suite passes (other suites will break — that's Tasks 2–4)**

Run: `xcodebuild test ... -only-testing:OurAppTests/CuisinePoolTests -quiet`
Expected: likely still FAIL to build the test target because `FoodDecisionFlow`/views still use `Cuisine(name:emoji:)`. **If so, proceed to Task 2 without committing** and note it in your report — Tasks 1+2 land as one commit in that case (the compiler forces it; the plan anticipates this).

- [ ] **Step 5: Commit** (alone if it built, or fold into Task 2's commit as noted)

```bash
git add -A
git commit -m "Make cuisine pool localized data with search terms"
```

---

### Task 2: Flow + record updates for localized cuisines (TDD)

**Files:**
- Modify: `OurApp/Modules/FoodDecision/FoodDecisionFlow.swift`
- Modify: `OurApp/Modules/FoodDecision/DecisionRecord.swift`
- Modify: `OurApp/Modules/FoodDecision/Views/ProposeView.swift`, `DecideView.swift`, `DecidedView.swift` (only the `cuisine.name` → `cuisine.displayName` touch-ups listed below)
- Test: `OurAppTests/FoodDecisionFlowTests.swift` (full rewrite below)

**Interfaces:**
- Consumes: `Cuisine`, `CuisinePool.match/draw` (Task 1).
- Produces: `FoodDecisionFlow` unchanged in surface except `proposeManual` resolves via `CuisinePool.match` and `agree(in:)` also stores `cuisineID`. `DecisionRecord` gains `var cuisineID: String?` with `init(date: Date = .now, cuisineChosen: String, cuisineID: String? = nil)` — **additive**; v1 rows load with `cuisineID == nil`.

- [ ] **Step 1: Rewrite `OurAppTests/FoodDecisionFlowTests.swift`**

```swift
import Testing
import SwiftData
@testable import OurApp

@MainActor
struct FoodDecisionFlowTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try Persistence.makeContainer(inMemory: true))
    }

    @Test func startsInProposePhase() {
        #expect(FoodDecisionFlow().phase == .propose)
    }

    @Test func proposeRandomMovesToDecidingWithAPoolCuisine() {
        let flow = FoodDecisionFlow()
        flow.proposeRandom()
        guard case .deciding(let cuisine) = flow.phase else {
            Issue.record("expected .deciding, got \(flow.phase)")
            return
        }
        #expect(CuisinePool.all.contains(cuisine))
    }

    @Test func proposeManualResolvesPoolEntryInAnyLanguage() {
        let flow = FoodDecisionFlow()
        flow.proposeManual("  火锅  ")
        guard case .deciding(let cuisine) = flow.phase else {
            Issue.record("expected .deciding, got \(flow.phase)")
            return
        }
        #expect(cuisine.id == "hotpot")
    }

    @Test func proposeManualKeepsUnknownTextAsCustom() {
        let flow = FoodDecisionFlow()
        flow.proposeManual("Xinjiang BBQ")
        guard case .deciding(let cuisine) = flow.phase else {
            Issue.record("expected .deciding, got \(flow.phase)")
            return
        }
        #expect(cuisine.isCustom)
        #expect(cuisine.displayName == "Xinjiang BBQ")
    }

    @Test func proposeManualIgnoresBlankInput() {
        let flow = FoodDecisionFlow()
        flow.proposeManual("   ")
        #expect(flow.phase == .propose)
    }

    @Test func rerollDrawsADifferentCuisineAndStaysDeciding() {
        let flow = FoodDecisionFlow()
        flow.proposeRandom()
        guard case .deciding(let first) = flow.phase else {
            Issue.record("expected .deciding, got \(flow.phase)")
            return
        }
        flow.reroll()
        guard case .deciding(let second) = flow.phase else {
            Issue.record("expected .deciding after reroll, got \(flow.phase)")
            return
        }
        #expect(second != first)
    }

    @Test func agreeOnPoolCuisineRecordsStableID() throws {
        let context = try makeContext()
        let flow = FoodDecisionFlow()
        flow.proposeManual("火锅")
        flow.agree(in: context)

        let records = try context.fetch(FetchDescriptor<DecisionRecord>())
        #expect(records.count == 1)
        #expect(records.first?.cuisineID == "hotpot")
        #expect(records.first?.cuisineChosen.isEmpty == false)
        guard case .decided(let cuisine) = flow.phase else {
            Issue.record("expected .decided, got \(flow.phase)")
            return
        }
        #expect(cuisine.id == "hotpot")
    }

    @Test func agreeOnCustomCuisineRecordsNilID() throws {
        let context = try makeContext()
        let flow = FoodDecisionFlow()
        flow.proposeManual("Xinjiang BBQ")
        flow.agree(in: context)

        let records = try context.fetch(FetchDescriptor<DecisionRecord>())
        #expect(records.first?.cuisineID == nil)
        #expect(records.first?.cuisineChosen == "Xinjiang BBQ")
    }

    @Test func legacyRecordsWithoutIDStillLoad() throws {
        let context = try makeContext()
        context.insert(DecisionRecord(cuisineChosen: "Hotpot"))
        try context.save()
        let records = try context.fetch(FetchDescriptor<DecisionRecord>())
        #expect(records.first?.cuisineID == nil)
        #expect(records.first?.cuisineChosen == "Hotpot")
    }

    @Test func agreeOutsideDecidingDoesNothing() throws {
        let context = try makeContext()
        let flow = FoodDecisionFlow()
        flow.agree(in: context)
        #expect(flow.phase == .propose)
        #expect(try context.fetch(FetchDescriptor<DecisionRecord>()).isEmpty)
    }

    @Test func startOverReturnsToPropose() {
        let flow = FoodDecisionFlow()
        flow.proposeRandom()
        flow.startOver()
        #expect(flow.phase == .propose)
    }
}
```

- [ ] **Step 2: Run to verify it fails** (`-only-testing:OurAppTests/FoodDecisionFlowTests`)

- [ ] **Step 3: Implement**

`OurApp/Modules/FoodDecision/DecisionRecord.swift` — replace the class body:

```swift
@Model
final class DecisionRecord {
    var date: Date
    var cuisineChosen: String
    /// Stable pool id (F6) so history survives language switches; nil for
    /// free-form typed cuisines and for all v1-era records (additive migration).
    var cuisineID: String?

    init(date: Date = .now, cuisineChosen: String, cuisineID: String? = nil) {
        self.date = date
        self.cuisineChosen = cuisineChosen
        self.cuisineID = cuisineID
    }
}
```

`OurApp/Modules/FoodDecision/FoodDecisionFlow.swift` — replace `proposeManual` and `agree`:

```swift
    /// Manual entry resolves across every language and search term (F6):
    /// 火锅 / Hotpot / 麻辣火锅 all land on the pool entry; unknown text stays
    /// as a free-form custom cuisine, exactly like v1.
    func proposeManual(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        phase = .deciding(CuisinePool.match(trimmed) ?? .custom(trimmed))
    }

    /// Agree seals the decision and silently records it (F4), now with the
    /// stable id so history is language-proof (F6).
    func agree(in context: ModelContext) {
        guard case .deciding(let cuisine) = phase else { return }
        context.insert(DecisionRecord(
            cuisineChosen: cuisine.displayName,
            cuisineID: cuisine.isCustom ? nil : cuisine.id
        ))
        try? context.save()
        phase = .decided(cuisine)
    }
```

View touch-ups (mechanical — `Cuisine.name` no longer exists):
- `DecideView.swift`: `Text(cuisine.name)` → `Text(cuisine.displayName)`
- `DecidedView.swift`: `Text("\(cuisine.name) it is! 🎉")` → `Text("\(cuisine.displayName) it is! 🎉")`
- `ProposeView.swift`: no `cuisine.name` references — verify only.
- `RestaurantSearch.swift`: the protocol still takes a `String` until Task 4 — change `provider.search(cuisine: cuisine.name)` to `provider.search(cuisine: cuisine.displayName)` so this task compiles.
- `RestaurantListView.swift`: every `search.cuisine.name` → `search.cuisine.displayName` (three interpolations).

- [ ] **Step 4: Full suite** — everything must compile and pass (31–33 tests depending on Task 1 fold-in).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Resolve manual entries across languages and record stable cuisine ids"
```

---

### Task 3: Module strings into the String Catalog (TDD-light)

**Files:**
- Modify: `OurApp/Resources/Localizable.xcstrings` (add the entries below; keep existing ones)
- Modify: `OurApp/Modules/FoodDecision/Views/ProposeView.swift`, `DecideView.swift`, `DecidedView.swift`, `RestaurantListView.swift`, `RestaurantCard.swift`, `MapKitRestaurantProvider.swift` (string literal swaps only)
- Test: `OurAppTests/LocalizationTests.swift` (add one test)

**Interfaces:**
- Consumes: catalog mechanics from the shell milestone.
- Produces: every module string localized. Keys and translations (character-for-character):

| Key | zh-Hans | zh-Hant |
|---|---|---|
| `Draw a cuisine, or type a craving.` | 抽一个菜系，或者输入你想吃的。 | 抽一個菜系，或者輸入你想吃的。 |
| `Surprise us` | 给我们个惊喜 | 給我們個驚喜 |
| `Or type a cuisine…` | 或者输入菜系… | 或者輸入菜系… |
| `Go` | 走起 | 走起 |
| `How about…` | 要不要吃… | 要不要吃… |
| `Hand the phone over 📱` | 把手机递给对方 📱 | 把手機遞給對方 📱 |
| `Agree` | 同意 | 同意 |
| `Re-roll` | 换一个 | 換一個 |
| `%@ it is! 🎉` | 就吃%@吧！🎉 | 就吃%@吧！🎉 |
| `Find places near us` | 找找附近的店 | 找找附近的店 |
| `Start over` | 重新开始 | 重新開始 |
| `Finding %@ near you…` | 正在找附近的%@… | 正在找附近的%@… |
| `Nothing nearby for %@` | 附近没有%@ | 附近沒有%@ |
| `Go back and try another cuisine — maybe re-roll?` | 回去换个菜系试试——要不要重新抽一个？ | 回去換個菜系試試——要不要重新抽一個？ |
| `We can't see where you are` | 我们看不到你在哪里 | 我們看不到你在哪裡 |
| `Allow location access in Settings and we'll find %@ nearby.` | 在设置里允许定位，我们就能找到附近的%@。 | 在設定裡允許定位，我們就能找到附近的%@。 |
| `Open Settings` | 打开设置 | 打開設定 |
| `Search hiccuped` | 搜索出了点小问题 | 搜尋出了點小問題 |
| `Check your connection and give it another go.` | 检查一下网络，再试一次吧。 | 檢查一下網路，再試一次吧。 |
| `Retry` | 重试 | 重試 |
| `Directions` | 导航 | 導航 |
| `Unnamed spot` | 无名小店 | 無名小店 |

- [ ] **Step 1: Add the failing test to `OurAppTests/LocalizationTests.swift`**

```swift
    @Test func foodModuleStringsAreTranslated() {
        #expect(localizedValue("Agree", language: "zh-Hans") == "同意")
        #expect(localizedValue("Re-roll", language: "zh-Hant") == "換一個")
        #expect(localizedValue("Find places near us", language: "zh-Hans") == "找找附近的店")
        #expect(localizedValue("Unnamed spot", language: "zh-Hant") == "無名小店")
    }
```

- [ ] **Step 2: Run to verify it fails** (`-only-testing:OurAppTests/LocalizationTests`)

- [ ] **Step 3: Add all 22 entries to the catalog** — same JSON shape as existing entries (`extractionState: "manual"`, en + zh-Hans + zh-Hant `stringUnit`s; en value = the key itself). Validate with `python3 -m json.tool OurApp/Resources/Localizable.xcstrings > /dev/null`.

- [ ] **Step 4: Swap literals in code**

SwiftUI `Text("literal")`/`Label("literal", ...)`/`TextField("literal", ...)`/`Button("literal")`/`ProgressView("literal")` calls already auto-key into the catalog — the code literals just need to match the keys exactly (they do; verify each file). Two non-view cases need explicit lookups:
- `MapKitRestaurantProvider.swift`: `?? "Unnamed spot"` → `?? String(localized: "Unnamed spot")`
- `RestaurantListView.swift` interpolated cases already auto-key (`Text("Finding \(...) near you…")` → key `Finding %@ near you…`) — but they interpolate `search.cuisine.name`: change to `search.cuisine.displayName` (three places) if Task 2 didn't already.

- [ ] **Step 5: Full suite green; commit**

```bash
git add -A
git commit -m "Localize all food decision module strings"
```

---

### Task 4: Provider takes the Cuisine; term ordering + merge/dedupe (TDD)

**Files:**
- Modify: `OurApp/Modules/FoodDecision/RestaurantProvider.swift` (protocol signature)
- Modify: `OurApp/Modules/FoodDecision/MapKitRestaurantProvider.swift` (add pure strategy functions; live search updated in Task 5)
- Modify: `OurApp/Modules/FoodDecision/RestaurantSearch.swift` (pass the Cuisine through)
- Test: `OurAppTests/RestaurantMappingTests.swift` (add tests), `OurAppTests/RestaurantSearchTests.swift` (mock signature)

**Interfaces:**
- Consumes: `Cuisine` (Task 1).
- Produces:
  ```swift
  protocol RestaurantProvider { @MainActor func search(for cuisine: Cuisine) async throws -> [Restaurant] }
  extension MapKitRestaurantProvider {
      static func orderedTerms(for cuisine: Cuisine, chineseSpeakingRegion: Bool) -> [String]
      static func merge(_ batches: [[Restaurant]], limit: Int = 8) -> [Restaurant]
  }
  ```
  `orderedTerms`: stable partition of `searchTerms` — CJK-containing terms first when `chineseSpeakingRegion`, Latin-first otherwise (original relative order preserved within each partition). `merge`: concatenates batches in order, dedupes by case-insensitive name + coordinates rounded to 4 decimal places, sorts by distance, caps at `limit`.

- [ ] **Step 1: Add failing tests**

Append to `OurAppTests/RestaurantMappingTests.swift`:

```swift
    private func restaurant(_ name: String, lat: Double, lon: Double, distance: Double) -> Restaurant {
        Restaurant(id: UUID(), name: name, distanceMeters: distance,
                   address: nil, phone: nil, latitude: lat, longitude: lon)
    }

    @Test func orderedTermsPutCJKFirstInChineseRegions() {
        let hotpot = CuisinePool.all.first { $0.id == "hotpot" }!
        let zhFirst = MapKitRestaurantProvider.orderedTerms(for: hotpot, chineseSpeakingRegion: true)
        #expect(zhFirst.first == "火锅")
        #expect(zhFirst.contains("hotpot"))
        let enFirst = MapKitRestaurantProvider.orderedTerms(for: hotpot, chineseSpeakingRegion: false)
        #expect(enFirst.first == "hotpot")
        #expect(Set(enFirst) == Set(zhFirst)) // same terms, different order
    }

    @Test func mergeDedupesAcrossBatchesByNameAndCoordinate() {
        let a = restaurant("Haidilao", lat: 42.34001, lon: -71.08001, distance: 300)
        let aDupe = restaurant("HAIDILAO", lat: 42.340012, lon: -71.080011, distance: 300)
        let b = restaurant("Little Sheep", lat: 42.35, lon: -71.09, distance: 800)
        let merged = MapKitRestaurantProvider.merge([[a], [aDupe, b]])
        #expect(merged.count == 2)
        #expect(merged.map(\.name) == ["Haidilao", "Little Sheep"]) // distance-sorted
    }

    @Test func mergeCapsAtTheLimit() {
        let many = (0..<12).map { restaurant("Spot \($0)", lat: 42.3, lon: -71.0, distance: Double(100 + $0)) }
            .enumerated().map { index, r in
                restaurant(r.name, lat: 42.3 + Double(index) * 0.01, lon: -71.0, distance: r.distanceMeters)
            }
        #expect(MapKitRestaurantProvider.merge([many]).count == 8)
    }
```

Update `OurAppTests/RestaurantSearchTests.swift`: `MockProvider.search(cuisine: String)` → `search(for cuisine: Cuisine)`; construct the test cuisine via `Cuisine.custom("Hotpot")` or the pool's hotpot; assertions unchanged.

- [ ] **Step 2: Run to verify failure** (compile errors on the new symbols).

- [ ] **Step 3: Implement**

`RestaurantProvider.swift`: protocol method becomes `@MainActor func search(for cuisine: Cuisine) async throws -> [Restaurant]` (doc comment: the provider owns the multi-term strategy — F7).

`MapKitRestaurantProvider.swift` — add:

```swift
    /// F7 term ordering: where you stand determines how POIs are tagged.
    /// Stable partition — original order preserved within each group.
    static func orderedTerms(for cuisine: Cuisine, chineseSpeakingRegion: Bool) -> [String] {
        let (cjk, latin) = cuisine.searchTerms.reduce(into: ([String](), [String]())) { result, term in
            if term.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) {
                result.0.append(term)
            } else {
                result.1.append(term)
            }
        }
        return chineseSpeakingRegion ? cjk + latin : latin + cjk
    }

    /// F7 merge: batches arrive in term-priority order; dedupe by
    /// case-insensitive name + ~11m coordinate cell, distance-sort, cap.
    static func merge(_ batches: [[Restaurant]], limit: Int = 8) -> [Restaurant] {
        var seen = Set<String>()
        var unique: [Restaurant] = []
        for restaurant in batches.flatMap({ $0 }) {
            let key = "\(restaurant.name.lowercased())|\(String(format: "%.4f", restaurant.latitude))|\(String(format: "%.4f", restaurant.longitude))"
            if seen.insert(key).inserted {
                unique.append(restaurant)
            }
        }
        return Array(unique.sorted { $0.distanceMeters < $1.distanceMeters }.prefix(limit))
    }
```

`RestaurantSearch.swift`: `run()` calls `provider.search(for: cuisine)`. Temporarily update the live `search(cuisine:)` in `MapKitRestaurantProvider` to `search(for cuisine: Cuisine)` using `cuisine.searchTerms.first ?? cuisine.displayName` as the single query (Task 5 replaces the body with the real multi-term strategy) — the suite must stay green between tasks.

- [ ] **Step 4: Full suite green; commit**

```bash
git add -A
git commit -m "Route search through cuisine terms with ordering and merge strategy"
```

---

### Task 5: Live multi-term, region-aware search

Live-services task (CLGeocoder + sequential MKLocalSearch): no new unit tests; everything testable landed in Task 4. Verification = full suite green.

**Files:**
- Modify: `OurApp/Modules/FoodDecision/MapKitRestaurantProvider.swift` (replace the live `search(for:)` body)

**Interfaces:**
- Consumes: `orderedTerms`, `merge`, `restaurants(from:userLocation:limit:)`, `LocationFetcher`.
- Produces: final `search(for:)` behavior — reverse-geocode country → Chinese-speaking region set `["CN", "TW", "HK", "MO", "SG"]` (device-locale region as fallback when geocoding fails) → query terms sequentially, merging until ≥8 unique results, early exit → `.noResults` only if every term returned nothing.

- [ ] **Step 1: Replace the `search(for:)` implementation**

```swift
extension MapKitRestaurantProvider: RestaurantProvider {
    /// F7: sequential multi-term search with early exit (open question resolved
    /// 2026-07-29). Region fit comes from where the user actually stands
    /// (reverse-geocoded country), falling back to the device locale — device
    /// language alone breaks when traveling.
    @MainActor
    func search(for cuisine: Cuisine) async throws -> [Restaurant] {
        let fetcher = LocationFetcher()
        let userLocation = try await fetcher.currentLocation()

        let chineseSpeaking = await Self.isChineseSpeakingRegion(around: userLocation)
        let terms = Self.orderedTerms(for: cuisine, chineseSpeakingRegion: chineseSpeaking)

        var batches: [[Restaurant]] = []
        var sawError: Error?
        for term in terms {
            do {
                batches.append(try await results(for: term, near: userLocation))
            } catch {
                sawError = error // a term can fail while another succeeds — fail soft
            }
            if Self.merge(batches).count >= 8 { break } // early exit at the cap
        }

        let merged = Self.merge(batches)
        if merged.isEmpty {
            if sawError != nil { throw RestaurantSearchError.searchFailed }
            throw RestaurantSearchError.noResults
        }
        return merged
    }

    private func results(for term: String, near userLocation: CLLocation) async throws -> [Restaurant] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = term
        request.resultTypes = .pointOfInterest
        // Food-adjacent categories so cafe/bakery/market-tagged cuisines
        // don't false-negative (final-review ruling, v1).
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket,
        ])
        request.region = MKCoordinateRegion(
            center: userLocation.coordinate,
            latitudinalMeters: 5_000,
            longitudinalMeters: 5_000
        )
        do {
            let response = try await MKLocalSearch(request: request).start()
            return Self.restaurants(from: response.mapItems, userLocation: userLocation, limit: 8)
        } catch {
            if let mkError = error as? MKError, mkError.code == .placemarkNotFound {
                return [] // this term found nothing; keep trying the others
            }
            throw RestaurantSearchError.searchFailed
        }
    }

    private static let chineseSpeakingCountries: Set<String> = ["CN", "TW", "HK", "MO", "SG"]

    /// Reverse-geocode the country the user is standing in; fall back to the
    /// device region if geocoding fails (offline, rate-limited).
    private static func isChineseSpeakingRegion(around location: CLLocation) async -> Bool {
        if let country = try? await CLGeocoder().reverseGeocodeLocation(location)
            .first?.isoCountryCode {
            return chineseSpeakingCountries.contains(country)
        }
        let fallback = Locale.current.region?.identifier ?? ""
        return chineseSpeakingCountries.contains(fallback)
    }
}
```

(Delete the Task 4 interim single-query body this replaces. `RestaurantSearchError` mapping semantics preserved: denied → `.locationDenied` from the fetcher; all-terms-empty → `.noResults`; term errors with zero results → `.searchFailed`.)

- [ ] **Step 2: Full suite green** (executed tests, not build-only); **commit**

```bash
git add -A
git commit -m "Search sequentially across region-ordered cuisine terms"
```

---

### Task 6: Theme adoption across module views

Build-order item 10's remaining half. Pure restyling — behavior identical, no new tests; verification = suite green + simulator screenshots (en + zh-Hant this time, exercising the other script).

**Files:**
- Modify: `OurApp/Modules/FoodDecision/Views/ProposeView.swift`, `DecideView.swift`, `DecidedView.swift`, `RestaurantListView.swift`, `RestaurantCard.swift`

- [ ] **Step 1: Apply the theme, view by view**

Shared treatment (apply to ProposeView, DecideView, DecidedView, and RestaurantListView's `Group`): add `.background(Theme.duskGradient.ignoresSafeArea())` at the outermost level; switch headline text to `Theme.display(...)` sizes already used (44/36/etc. stay); set `.tint(Theme.rose)` on each screen's outermost container so buttons inherit the palette; keep the green Agree tint (it's semantic).

Specifics:
- `ProposeView`: title `.font(Theme.display(34))` + `.foregroundStyle(.white)`; subtitle `.foregroundStyle(.white.opacity(0.7))`; wrap the manual-entry HStack in `.padding(12).glassCard(cornerRadius: 20)`; `TextField` keeps `.textFieldStyle(.plain)` (switch from `.roundedBorder`) with `.foregroundStyle(.white)`; "Surprise us" button keeps `.borderedProminent`. Add `Haptics.tap()` inside the surprise button action before `flow.proposeRandom()`.
- `DecideView`: "How about…" + cuisine name `.foregroundStyle(.white)` / `.white.opacity(0.7)` for hints; wrap the emoji+name VStack in `.padding(28).glassCard(cornerRadius: 28)`; `Haptics.tap()` in the re-roll action, `Haptics.success()` in the agree action (before calling flow methods).
- `DecidedView`: celebration text `.foregroundStyle(.white)`; keep `sensoryFeedback`.
- `RestaurantListView`: status views' text `.foregroundStyle(.white)` / secondary → `.white.opacity(0.7)`; `ProgressView` gets `.tint(.white)` + white label.
- `RestaurantCard`: replace `.background(Color(uiColor: .secondarySystemBackground), in: ...)` with `.glassCard(cornerRadius: 16)`; name/labels `.foregroundStyle(.white)` with secondary text `.white.opacity(0.7)`.
- `FoodDecisionModuleView` (`FoodDecisionModule.swift`): give the `NavigationStack` content `.background(Theme.duskGradient.ignoresSafeArea())` too, so pushed screens keep the backdrop, and `.toolbarColorScheme(.dark, for: .navigationBar)` on `RestaurantListView`'s nav title so it reads on the gradient.

- [ ] **Step 2: Full suite green**

- [ ] **Step 3: Simulator screenshots**

```bash
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
xcodebuild build -project OurApp.xcodeproj -scheme OurApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build -quiet
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/OurApp.app
SCRATCH=/private/tmp/claude-501/-Users-meixiaobin-Desktop-Our-App/814bea34-874e-4648-9367-b630a0384bc0/scratchpad
xcrun simctl launch booted com.ourapp.OurApp -openDrawer; sleep 4
xcrun simctl io booted screenshot "$SCRATCH/v2-drawer.png"
xcrun simctl terminate booted com.ourapp.OurApp
xcrun simctl launch booted com.ourapp.OurApp -openDrawer -AppleLanguages "(zh-Hant)" -AppleLocale zh_TW; sleep 4
xcrun simctl io booted screenshot "$SCRATCH/v2-drawer-zhHant.png"
```

READ both screenshots: the zh-Hant run must show 我們的空間 and 吃點什麼好？ (Traditional characters). Describe what you see in the report. (The module's themed screens can't be reached by scripted taps — the human checklist covers them; previews + suite cover compilation.)

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Dress food decision module in the platform theme"
```

---

### Task 7: Docs closure

**Files:**
- Modify: `docs/modules/food-decision.md`

- [ ] **Step 1: Update the module doc**
- Build order: mark items 7, 8, 9 with `~~…~~ ✅ (2026-07-29)` strikethrough-done, and item 10's remaining "Theme adoption" → `✅ (2026-07-29)`.
- Open questions: mark the two v2 leans resolved:
  - multi-term search → **Resolved for v2 (2026-07-29): sequential with early exit at the cap.**
  - region fit → **Resolved for v2 (2026-07-29): reverse-geocoded search location first, device region fallback.**
- Definition of done (v2): leave text; add `*(Met in build — pending the human's tri-language on-device pass.)*` beneath it.

- [ ] **Step 2: Also update `docs/DESIGN.md` §6** — food row status → `🚧 v2 built — tri-language + Chinese search, in trial`.

- [ ] **Step 3: Final full suite green (executed test summary). Commit**

```bash
git add -A
git commit -m "Record food decision v2 completion in docs"
```
