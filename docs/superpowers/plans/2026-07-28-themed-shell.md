# Themed Platform Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the platform's themed couples home — dreamy animated background, partner identity + "together for N days" counter, frosted-glass module launcher — plus the core theme system and tri-language localization infrastructure, per docs/DESIGN.md §4 (P4–P7).

**Architecture:** Everything here is *core*, not a module: a `Theme` token set and glass styling every screen consumes; a `CoupleIdentityStore` persisting names/anniversary/photos to local settings (P6); a `ModuleDescriptor` contract the launcher uses to mount modules; and a `CouplesHomeView` composing background + identity + launcher. The existing FoodDecision module is untouched except for exposing tile metadata. All user-facing strings go through one String Catalog (en / zh-Hans / zh-Hant, P5). The dreamy background is **procedurally drawn in SwiftUI** (animated gradients + Canvas particles + CoreMotion parallax) — original by construction, no image assets, $0.

**Tech Stack:** SwiftUI, Observation, CoreMotion (parallax), PhotosUI (avatar picker), String Catalog (`.xcstrings`), Swift Testing.

## Global Constraints

- Working directory `/Users/meixiaobin/Desktop/Our-App`, branch `themed-shell`.
- iOS deployment target **17.0** (no iOS-18-only API like `MeshGradient`). Build/test on the **iPhone 17 Pro** simulator, Xcode 26.2.
- $0 rule: no packages, no paid services, no image assets bought or lifted — background art is code-drawn.
- Synchronized folder groups: new files under `OurApp/`/`OurAppTests/` are auto-included; **never edit `project.pbxproj`** — with ONE exception in Task 1 (adding `zh-Hans`/`zh-Hant` to `knownRegions`, an exact-string edit specified there).
- **Every user-facing string** added by this plan must exist in `OurApp/Resources/Localizable.xcstrings` with en, zh-Hans, and zh-Hant values (platform principle 8 / P5). No hardcoded user-visible literals outside the catalog's keys.
- Module contract holds: shell never reaches into module internals; the only touch point is `FoodDecisionModule.descriptor`.
- Commit messages: plain imperative English, **NO AI attribution of any kind**.
- Full suite command: `xcodebuild test -project OurApp.xcodeproj -scheme OurApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet` (up to 10 min; scope with `-only-testing:OurAppTests/<Suite>` for TDD loops).

---

### Task 1: Localization infrastructure (String Catalog + knownRegions)

All shell strings, pre-translated, land here first so every later task just uses them.

**Files:**
- Create: `OurApp/Resources/Localizable.xcstrings`
- Modify: `OurApp.xcodeproj/project.pbxproj` (knownRegions only — exact edit below)
- Test: `OurAppTests/LocalizationTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: catalog keys later tasks reference verbatim in SwiftUI `Text`/labels: `"Together for %lld days"`, `"Set your anniversary"`, `"Add your names"`, `"Our space"`, `"Our details"`, `"Name"`, `"Photo"`, `"Anniversary"`, `"Done"`, `"Close"`, `"Choose a photo"`, `"Me"`, `"My love"`, `"What should we eat?"`. SwiftUI auto-extracts string literals in `Text("…")` as catalog keys — that's why keys are the English literals (non-obvious bit for the TS-minded: the key IS the source string, not a dotted ID).

- [ ] **Step 1: Write the failing test `OurAppTests/LocalizationTests.swift`**

```swift
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
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project OurApp.xcodeproj -scheme OurApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OurAppTests/LocalizationTests -quiet`
Expected: FAIL — no zh-Hans/zh-Hant lproj in the bundle yet.

- [ ] **Step 3: Create `OurApp/Resources/Localizable.xcstrings`**

The String Catalog is JSON (non-obvious: `extractionState: "manual"` stops Xcode pruning entries whose code references land in later tasks; the plural entry uses `variations.plural` — Chinese needs no plural forms, English does):

```json
{
  "sourceLanguage" : "en",
  "strings" : {
    "Together for %lld days" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "variations" : { "plural" : {
          "one" : { "stringUnit" : { "state" : "translated", "value" : "Together for %lld day" } },
          "other" : { "stringUnit" : { "state" : "translated", "value" : "Together for %lld days" } }
        } } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "在一起 %lld 天" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "在一起 %lld 天" } }
      }
    },
    "Set your anniversary" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Set your anniversary" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "设置纪念日" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "設定紀念日" } }
      }
    },
    "Add your names" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Add your names" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "填写我们的名字" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "填寫我們的名字" } }
      }
    },
    "Our space" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Our space" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "我们的空间" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "我們的空間" } }
      }
    },
    "Our details" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Our details" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "我们的资料" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "我們的資料" } }
      }
    },
    "Name" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Name" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "名字" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "名字" } }
      }
    },
    "Photo" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Photo" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "照片" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "照片" } }
      }
    },
    "Anniversary" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Anniversary" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "纪念日" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "紀念日" } }
      }
    },
    "Done" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Done" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "完成" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "完成" } }
      }
    },
    "Close" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Close" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "关闭" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "關閉" } }
      }
    },
    "Choose a photo" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Choose a photo" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "选择照片" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "選擇照片" } }
      }
    },
    "Me" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Me" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "我" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "我" } }
      }
    },
    "My love" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "My love" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "我的爱人" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "我的愛人" } }
      }
    },
    "What should we eat?" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "What should we eat?" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "吃点什么好？" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "吃點什麼好？" } }
      }
    }
  },
  "version" : "1.0"
}
```

- [ ] **Step 4: knownRegions edit in `OurApp.xcodeproj/project.pbxproj`**

The ONLY permitted pbxproj edit. Replace exactly:

```
			knownRegions = (
				en,
				Base,
			);
```

with:

```
			knownRegions = (
				en,
				Base,
				"zh-Hans",
				"zh-Hant",
			);
```

- [ ] **Step 5: Run test to verify it passes**

Run: same command as Step 2.
Expected: PASS (both tests). If `appShipsAllThreeLanguages` fails, the catalog wasn't picked up — confirm the file is under `OurApp/` (synchronized group) and named exactly `Localizable.xcstrings`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add tri-language String Catalog and localization test"
```

---

### Task 2: Core theme system

Design tokens + glass styling + haptic helpers (P7 / principle 9). No user-facing strings, no unit-testable logic — verification is the suite still building green plus previews compiling.

**Files:**
- Create: `OurApp/Core/Theme/Theme.swift`
- Create: `OurApp/Core/Theme/GlassStyle.swift`
- Create: `OurApp/Core/Theme/Haptics.swift`

**Interfaces:**
- Consumes: nothing.
- Produces (used verbatim by Tasks 4–8): `Theme.indigo/.violet/.rose/.peach/.glow: Color`; `Theme.duskGradient: LinearGradient`; `Theme.springy: Animation`; `Theme.gentle: Animation`; `Theme.display(_ size: CGFloat) -> Font`; `View.glassCard(cornerRadius: CGFloat = 24)`; `Haptics.tap()`, `Haptics.success()`.

- [ ] **Step 1: Write `OurApp/Core/Theme/Theme.swift`**

```swift
import SwiftUI

/// The platform's shared design language (principle 9, decision P7).
/// One place to tune the feel — shell and modules consume these tokens.
enum Theme {
    // MARK: Palette — "dusk dream": deep indigo through rose into peach glow.
    static let indigo = Color(red: 0.16, green: 0.13, blue: 0.35)
    static let violet = Color(red: 0.35, green: 0.20, blue: 0.55)
    static let rose = Color(red: 0.85, green: 0.45, blue: 0.60)
    static let peach = Color(red: 0.98, green: 0.75, blue: 0.60)
    static let glow = Color(red: 1.00, green: 0.92, blue: 0.85)

    /// Full-bleed base gradient for shell backgrounds.
    static let duskGradient = LinearGradient(
        colors: [indigo, violet, rose, peach],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: Motion
    static let springy = Animation.spring(duration: 0.45, bounce: 0.35)
    static let gentle = Animation.easeInOut(duration: 0.8)

    // MARK: Type
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}
```

- [ ] **Step 2: Write `OurApp/Core/Theme/GlassStyle.swift`**

```swift
import SwiftUI

/// Frosted-glass surface used by the launcher drawer, tiles, and floating buttons.
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

#Preview {
    Text("Glass")
        .padding(40)
        .glassCard()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.duskGradient)
}
```

- [ ] **Step 3: Write `OurApp/Core/Theme/Haptics.swift`**

```swift
import UIKit

/// Tasteful haptics (principle 9): soft taps for interactions, success on milestones.
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
```

- [ ] **Step 4: Verify build + suite**

Run: the full suite command (Global Constraints).
Expected: PASS — everything compiles, all prior tests green.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add core theme tokens, glass styling, and haptic helpers"
```

---

### Task 3: DaysTogether + CoupleIdentityStore (TDD)

The shell's testable logic: day counting and local-settings persistence (P6).

**Files:**
- Create: `OurApp/Core/CoupleIdentity/DaysTogether.swift`
- Create: `OurApp/Core/CoupleIdentity/CoupleIdentityStore.swift`
- Test: `OurAppTests/CoupleIdentityTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces (used verbatim by Tasks 5 & 8):
  ```swift
  enum DaysTogether { static func days(from anniversary: Date, to now: Date = .now, calendar: Calendar = .current) -> Int }
  enum Partner: String, CaseIterable { case one, two }
  @MainActor @Observable final class CoupleIdentityStore {
      var nameOne: String        // persists on set
      var nameTwo: String        // persists on set
      var anniversary: Date?     // persists on set
      private(set) var avatars: [Partner: UIImage]
      init(defaults: UserDefaults = .standard, directory: URL? = nil)
      func setAvatar(_ data: Data, for partner: Partner) throws
  }
  ```

- [ ] **Step 1: Write the failing test `OurAppTests/CoupleIdentityTests.swift`**

```swift
import Foundation
import Testing
import UIKit
@testable import OurApp

@MainActor
struct CoupleIdentityTests {
    private func makeStore(suite: String, directory: URL) -> CoupleIdentityStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return CoupleIdentityStore(defaults: defaults, directory: directory)
    }

    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: DaysTogether

    @Test func anniversaryDayItselfIsDayOne() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        #expect(DaysTogether.days(from: now, to: now) == 1)
    }

    @Test func nextCalendarDayIsDayTwo() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1, hour: 23))!
        let next = calendar.date(from: DateComponents(year: 2026, month: 7, day: 2, hour: 1))!
        #expect(DaysTogether.days(from: start, to: next, calendar: calendar) == 2)
    }

    @Test func countsAcrossAYear() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2025, month: 7, day: 28))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 28))!
        #expect(DaysTogether.days(from: start, to: now, calendar: calendar) == 366)
    }

    @Test func futureAnniversaryClampsToOne() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let future = now.addingTimeInterval(86_400 * 30)
        #expect(DaysTogether.days(from: future, to: now) == 1)
    }

    // MARK: CoupleIdentityStore

    @Test func namesAndAnniversaryRoundTrip() throws {
        let suite = "test.\(UUID().uuidString)"
        let dir = try tempDirectory()
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let store = CoupleIdentityStore(defaults: defaults, directory: dir)
        store.nameOne = "小彬"
        store.nameTwo = "Mei"
        let date = Date(timeIntervalSinceReferenceDate: 700_000_000)
        store.anniversary = date

        let reloaded = CoupleIdentityStore(defaults: defaults, directory: dir)
        #expect(reloaded.nameOne == "小彬")
        #expect(reloaded.nameTwo == "Mei")
        #expect(reloaded.anniversary == date)
    }

    @Test func avatarPersistsToDiskAndReloads() throws {
        let suite = "test.\(UUID().uuidString)"
        let dir = try tempDirectory()
        let store = makeStore(suite: suite, directory: dir)

        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        try store.setAvatar(image.jpegData(compressionQuality: 0.9)!, for: .one)
        #expect(store.avatars[.one] != nil)

        let reloaded = makeStore(suite: suite, directory: dir)
        #expect(reloaded.avatars[.one] != nil)
        #expect(reloaded.avatars[.two] == nil)
    }
}
```

Note the second `makeStore` in `avatarPersistsToDiskAndReloads` wipes the defaults domain but not the directory — avatars live on disk, so the reload must still find partner one's file. That asymmetry is the point of the test.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test ... -only-testing:OurAppTests/CoupleIdentityTests -quiet`
Expected: FAIL — `cannot find 'DaysTogether' in scope` / `cannot find 'CoupleIdentityStore' in scope`.

- [ ] **Step 3: Implement `OurApp/Core/CoupleIdentity/DaysTogether.swift`**

```swift
import Foundation

/// Day math for the "together for N days" counter.
enum DaysTogether {
    /// The anniversary itself counts as day 1 (how couples actually count).
    /// Compares calendar days, not 24h intervals, so the number rolls at midnight.
    static func days(from anniversary: Date, to now: Date = .now, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: anniversary)
        let end = calendar.startOfDay(for: now)
        let diff = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return max(diff + 1, 1)
    }
}
```

- [ ] **Step 4: Implement `OurApp/Core/CoupleIdentity/CoupleIdentityStore.swift`**

```swift
import Foundation
import Observation
import UIKit

enum Partner: String, CaseIterable {
    case one, two
}

/// Couple identity in local settings (decision P6): names + anniversary in
/// UserDefaults, avatar photos as image files on disk. No pairing/sync —
/// the data model is deliberately tiny so migrating into synced core data
/// later is mechanical (see DESIGN.md §7).
@MainActor
@Observable
final class CoupleIdentityStore {
    private enum Keys {
        static let nameOne = "couple.nameOne"
        static let nameTwo = "couple.nameTwo"
        static let anniversary = "couple.anniversary"
    }

    var nameOne: String {
        didSet { defaults.set(nameOne, forKey: Keys.nameOne) }
    }
    var nameTwo: String {
        didSet { defaults.set(nameTwo, forKey: Keys.nameTwo) }
    }
    var anniversary: Date? {
        didSet {
            if let anniversary {
                defaults.set(anniversary.timeIntervalSinceReferenceDate, forKey: Keys.anniversary)
            } else {
                defaults.removeObject(forKey: Keys.anniversary)
            }
        }
    }
    private(set) var avatars: [Partner: UIImage] = [:]

    private let defaults: UserDefaults
    private let directory: URL

    /// `directory` is injectable for tests; the default is Application Support,
    /// which unlike Documents isn't user-visible in the Files app.
    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoupleIdentity", isDirectory: true)

        nameOne = defaults.string(forKey: Keys.nameOne) ?? ""
        nameTwo = defaults.string(forKey: Keys.nameTwo) ?? ""
        if defaults.object(forKey: Keys.anniversary) != nil {
            anniversary = Date(timeIntervalSinceReferenceDate: defaults.double(forKey: Keys.anniversary))
        }
        for partner in Partner.allCases {
            if let image = UIImage(contentsOfFile: avatarURL(for: partner).path) {
                avatars[partner] = image
            }
        }
    }

    func setAvatar(_ data: Data, for partner: Partner) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: avatarURL(for: partner), options: .atomic)
        avatars[partner] = UIImage(data: data)
    }

    private func avatarURL(for partner: Partner) -> URL {
        directory.appendingPathComponent("avatar-\(partner.rawValue).img")
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: same command as Step 2. Expected: PASS (6 tests).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add days-together math and couple identity store"
```

---

### Task 4: ModuleDescriptor + FoodDecision tile metadata (TDD)

The launcher's contract with modules — the "tile metadata" line added to the module contract in DESIGN.md §4.

**Files:**
- Create: `OurApp/Core/Modules/ModuleDescriptor.swift`
- Modify: `OurApp/Modules/FoodDecision/FoodDecisionModule.swift` (append the enum at the end)
- Test: `OurAppTests/ModuleDescriptorTests.swift`

**Interfaces:**
- Consumes: `FoodDecisionModuleView` (exists).
- Produces:
  ```swift
  struct ModuleDescriptor: Identifiable {
      let id: String
      let name: LocalizedStringResource
      let emoji: String
      let makeEntryView: @MainActor () -> AnyView
  }
  enum FoodDecisionModule { @MainActor static var descriptor: ModuleDescriptor }
  ```

- [ ] **Step 1: Write the failing test `OurAppTests/ModuleDescriptorTests.swift`**

```swift
import Testing
@testable import OurApp

@MainActor
struct ModuleDescriptorTests {
    @Test func foodDecisionExposesItsTile() {
        let descriptor = FoodDecisionModule.descriptor
        #expect(descriptor.id == "food-decision")
        #expect(descriptor.emoji == "🍽️")
        #expect(String(localized: descriptor.name) == "What should we eat?")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test ... -only-testing:OurAppTests/ModuleDescriptorTests -quiet`
Expected: FAIL — `cannot find 'FoodDecisionModule' in scope`.

- [ ] **Step 3: Implement `OurApp/Core/Modules/ModuleDescriptor.swift`**

```swift
import SwiftUI

/// What a module hands the shell so the launcher can show and mount it
/// (module contract, DESIGN.md §4). Nothing else crosses the seam.
struct ModuleDescriptor: Identifiable {
    let id: String
    /// Localized via the String Catalog — the launcher renders it directly.
    let name: LocalizedStringResource
    let emoji: String
    /// Type-erased so the shell never knows concrete module view types.
    let makeEntryView: @MainActor () -> AnyView
}
```

- [ ] **Step 4: Append to `OurApp/Modules/FoodDecision/FoodDecisionModule.swift`**

```swift
/// Tile metadata for the shell's launcher (module contract).
enum FoodDecisionModule {
    @MainActor static var descriptor: ModuleDescriptor {
        ModuleDescriptor(
            id: "food-decision",
            name: "What should we eat?",
            emoji: "🍽️",
            makeEntryView: { AnyView(FoodDecisionModuleView()) }
        )
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: same command as Step 2. Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add module descriptor contract and food decision tile metadata"
```

---

### Task 5: DreamyBackground (gradients + particles + parallax)

Pure visual core — verified by compilation, previews, and Task 8's screenshots.

**Files:**
- Create: `OurApp/Core/Shell/DreamyBackground.swift`
- Create: `OurApp/Core/Shell/TiltModel.swift`

**Interfaces:**
- Consumes: `Theme` (Task 2).
- Produces: `DreamyBackground(parallax: CGSize = .zero)` (a `View`); `@MainActor @Observable final class TiltModel { private(set) var offset: CGSize; func start(); func stop() }`.

- [ ] **Step 1: Implement `OurApp/Core/Shell/TiltModel.swift`**

```swift
import CoreMotion
import Observation
import SwiftUI

/// Gentle parallax from device tilt. Non-obvious bits: CMMotionManager must be
/// kept alive (it stops reporting if deallocated), updates are delivered on the
/// main queue so the @Observable write is safe, and start()/stop() bracket the
/// home's visibility so we never burn battery while a module is open.
/// On the simulator there's no motion hardware — offset just stays .zero.
@MainActor
@Observable
final class TiltModel {
    private let manager = CMMotionManager()
    private(set) var offset: CGSize = .zero

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let attitude = motion?.attitude else { return }
            // ±12pt max drift; roll/pitch are in radians, small angles ≈ linear.
            self?.offset = CGSize(
                width: max(-12, min(12, attitude.roll * 18)),
                height: max(-12, min(12, attitude.pitch * 18))
            )
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        offset = .zero
    }
}
```

- [ ] **Step 2: Implement `OurApp/Core/Shell/DreamyBackground.swift`**

```swift
import SwiftUI

/// The shell's full-bleed art, drawn in code (original by construction — no
/// image assets): the dusk gradient, two slowly drifting radial glows, and a
/// field of soft drifting particles. TimelineView re-renders ~30fps; all motion
/// derives from wall-clock time so it's smooth and stateless.
struct DreamyBackground: View {
    var parallax: CGSize = .zero

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Theme.duskGradient

                // Two big soft glows drifting on slow, incommensurate orbits.
                glow(color: Theme.rose.opacity(0.55), radius: 320,
                     x: 0.30 + 0.10 * sin(t / 11), y: 0.28 + 0.06 * cos(t / 13))
                    .offset(x: parallax.width, y: parallax.height)
                glow(color: Theme.peach.opacity(0.45), radius: 260,
                     x: 0.72 + 0.08 * cos(t / 9), y: 0.62 + 0.07 * sin(t / 15))
                    .offset(x: parallax.width * 1.6, y: parallax.height * 1.6)

                ParticleField(time: t)
                    .offset(x: parallax.width * 0.6, y: parallax.height * 0.6)
            }
        }
        .ignoresSafeArea()
    }

    private func glow(color: Color, radius: CGFloat, x: Double, y: Double) -> some View {
        GeometryReader { geo in
            RadialGradient(colors: [color, .clear], center: .center,
                           startRadius: 0, endRadius: radius)
                .frame(width: radius * 2, height: radius * 2)
                .position(x: geo.size.width * x, y: geo.size.height * y)
        }
    }
}

/// Drifting soft dots. Each particle's path is a pure function of (seed, time),
/// wrapping vertically — no per-frame state, no allocations in the draw loop.
private struct ParticleField: View {
    let time: TimeInterval
    private static let seeds: [(x: Double, speed: Double, size: Double, phase: Double)] =
        (0..<26).map { i in
            var generator = SeededGenerator(seed: UInt64(i) &* 0x9E37_79B9)
            return (
                x: Double.random(in: 0.02...0.98, using: &generator),
                speed: Double.random(in: 8...26, using: &generator),
                size: Double.random(in: 2.5...7, using: &generator),
                phase: Double.random(in: 0...1, using: &generator)
            )
        }

    var body: some View {
        Canvas { context, size in
            for seed in Self.seeds {
                let progress = (seed.phase + time / seed.speed).truncatingRemainder(dividingBy: 1)
                let y = size.height * (1.05 - progress * 1.1)
                let x = size.width * seed.x + sin(time / 4 + seed.phase * 10) * 14
                let rect = CGRect(x: x, y: y, width: seed.size, height: seed.size)
                context.opacity = 0.20 + 0.25 * sin(progress * .pi)
                context.fill(
                    Circle().path(in: rect),
                    with: .color(Theme.glow)
                )
            }
        }
        .allowsHitTesting(false)
    }
}

/// Deterministic RNG so the particle layout is stable across launches.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

#Preview {
    DreamyBackground()
}
```

- [ ] **Step 3: Verify build + suite**

Run: the full suite command. Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Add code-drawn dreamy background with particles and tilt parallax"
```

---

### Task 6: Identity header, together counter, settings sheet

**Files:**
- Create: `OurApp/Core/Shell/PartnerAvatarsView.swift`
- Create: `OurApp/Core/Shell/TogetherCounterView.swift`
- Create: `OurApp/Core/Shell/CoupleSettingsSheet.swift`

**Interfaces:**
- Consumes: `CoupleIdentityStore`, `Partner`, `DaysTogether` (Task 3); `Theme`, `glassCard`, `Haptics` (Task 2); catalog keys (Task 1).
- Produces: `PartnerAvatarsView(identity: CoupleIdentityStore)`; `TogetherCounterView(anniversary: Date)`; `CoupleSettingsSheet(identity: CoupleIdentityStore)` (presented in a `.sheet`).

- [ ] **Step 1: Implement `OurApp/Core/Shell/PartnerAvatarsView.swift`**

```swift
import SwiftUI

/// The two of us: avatar photos (or monogram circles) with names, a softly
/// pulsing heart between.
struct PartnerAvatarsView: View {
    let identity: CoupleIdentityStore
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 24) {
            avatar(for: .one, name: identity.nameOne, fallback: "Me")
            Text("💞")
                .font(.system(size: 34))
                .scaleEffect(pulse ? 1.15 : 0.95)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse = true }
            avatar(for: .two, name: identity.nameTwo, fallback: "My love")
        }
    }

    private func avatar(for partner: Partner, name: String, fallback: LocalizedStringKey) -> some View {
        VStack(spacing: 8) {
            Group {
                if let image = identity.avatars[partner] {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    // Monogram fallback: first character of the name, or a heart.
                    Text(name.isEmpty ? "♡" : String(name.prefix(1)))
                        .font(Theme.display(34))
                        .foregroundStyle(Theme.glow)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.white.opacity(0.12))
                }
            }
            .frame(width: 92, height: 92)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 2))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)

            if name.isEmpty {
                Text(fallback)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                Text(name)
                    .font(Theme.display(18))
                    .foregroundStyle(.white)
            }
        }
    }
}

#Preview {
    PartnerAvatarsView(identity: CoupleIdentityStore())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.duskGradient)
}
```

- [ ] **Step 2: Implement `OurApp/Core/Shell/TogetherCounterView.swift`**

```swift
import SwiftUI

/// Animated "Together for N days". Counts up from 0 with an ease-out ramp on
/// appear; `.contentTransition(.numericText)` makes the digits roll rather
/// than crossfade (non-obvious SwiftUI nicety).
struct TogetherCounterView: View {
    let anniversary: Date
    @State private var shown = 0

    var body: some View {
        Text("Together for \(shown) days")
            .font(Theme.display(24))
            .foregroundStyle(.white)
            .contentTransition(.numericText(value: Double(shown)))
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .glassCard(cornerRadius: 22)
            .task { await countUp() }
    }

    private func countUp() async {
        let target = DaysTogether.days(from: anniversary)
        let frames = 36
        for frame in 1...frames {
            // Ease-out cubic: fast start, gentle landing on the real number.
            let progress = 1 - pow(1 - Double(frame) / Double(frames), 3)
            let value = Int(Double(target) * progress)
            withAnimation(.snappy(duration: 0.05)) { shown = value }
            try? await Task.sleep(for: .milliseconds(33))
        }
        withAnimation(Theme.springy) { shown = target }
        Haptics.success()
    }
}

#Preview {
    TogetherCounterView(anniversary: .now.addingTimeInterval(-86_400 * 500))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.duskGradient)
}
```

- [ ] **Step 3: Implement `OurApp/Core/Shell/CoupleSettingsSheet.swift`**

```swift
import PhotosUI
import SwiftUI

/// Edit names, anniversary, and avatar photos — the whole of "couple identity"
/// (P6, local settings only). PhotosPicker runs out-of-process, so no photo
/// library permission or Info.plist key is needed (non-obvious but true).
struct CoupleSettingsSheet: View {
    @Bindable var identity: CoupleIdentityStore
    @Environment(\.dismiss) private var dismiss
    @State private var pickedItem: PhotosPickerItem?
    @State private var pickingFor: Partner?

    var body: some View {
        NavigationStack {
            Form {
                partnerSection(header: "Me", name: $identity.nameOne, partner: .one)
                partnerSection(header: "My love", name: $identity.nameTwo, partner: .two)

                Section("Anniversary") {
                    DatePicker(
                        "Anniversary",
                        selection: Binding(
                            get: { identity.anniversary ?? .now },
                            set: { identity.anniversary = $0 }
                        ),
                        in: ...Date.now,
                        displayedComponents: .date
                    )
                }
            }
            .navigationTitle(Text("Our details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .photosPicker(
                isPresented: Binding(
                    get: { pickingFor != nil },
                    set: { if !$0 { pickingFor = nil } }
                ),
                selection: $pickedItem,
                matching: .images
            )
            .onChange(of: pickedItem) {
                guard let item = pickedItem, let partner = pickingFor else { return }
                Task {
                    // loadTransferable is async & throwing; failures just leave
                    // the old avatar in place (fail soft).
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        try? identity.setAvatar(data, for: partner)
                    }
                    pickedItem = nil
                    pickingFor = nil
                }
            }
        }
    }

    private func partnerSection(header: LocalizedStringKey, name: Binding<String>, partner: Partner) -> some View {
        Section(header) {
            TextField("Name", text: name)
            Button {
                pickingFor = partner
            } label: {
                HStack {
                    Text("Choose a photo")
                    Spacer()
                    if let image = identity.avatars[partner] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "photo.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

#Preview {
    CoupleSettingsSheet(identity: CoupleIdentityStore())
}
```

- [ ] **Step 4: Verify build + suite**

Run: the full suite command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add partner avatars, animated together counter, and couple settings sheet"
```

---

### Task 7: Module launcher drawer + module host

**Files:**
- Create: `OurApp/Core/Shell/ModuleLauncherDrawer.swift`
- Create: `OurApp/Core/Shell/ModuleHostView.swift`

**Interfaces:**
- Consumes: `ModuleDescriptor` (Task 4); `Theme`, `glassCard`, `Haptics` (Task 2); catalog keys (Task 1).
- Produces: `ModuleLauncherDrawer(modules: [ModuleDescriptor], openModule: Binding<ModuleDescriptor?>, startsOpen: Bool = false)`; `ModuleHostView(module: ModuleDescriptor)` (used in `.fullScreenCover(item:)`).

- [ ] **Step 1: Implement `OurApp/Core/Shell/ModuleLauncherDrawer.swift`**

```swift
import SwiftUI

/// The frosted-glass drawer at the bottom of the home (decision P4). Tap or
/// drag it to swap open and reveal the module tiles; tapping a tile mounts
/// that module full-screen via the `openModule` binding.
struct ModuleLauncherDrawer: View {
    let modules: [ModuleDescriptor]
    @Binding var openModule: ModuleDescriptor?
    var startsOpen = false

    @State private var isOpen = false

    var body: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(.white.opacity(0.5))
                .frame(width: 44, height: 5)
            Text("Our space")
                .font(Theme.display(17))
                .foregroundStyle(.white.opacity(0.9))

            if isOpen {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 14)], spacing: 14) {
                    ForEach(modules) { module in
                        tile(module)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 32)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture { toggle() }
        .gesture(
            DragGesture(minimumDistance: 20).onEnded { value in
                withAnimation(Theme.springy) { isOpen = value.translation.height < 0 }
            }
        )
        .onAppear { if startsOpen { isOpen = true } }
    }

    private func toggle() {
        Haptics.tap()
        withAnimation(Theme.springy) { isOpen.toggle() }
    }

    private func tile(_ module: ModuleDescriptor) -> some View {
        Button {
            Haptics.tap()
            openModule = module
        } label: {
            VStack(spacing: 8) {
                Text(module.emoji)
                    .font(.system(size: 40))
                Text(module.name)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
            }
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .glassCard(cornerRadius: 20)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    struct Host: View {
        @State var open: ModuleDescriptor?
        var body: some View {
            ModuleLauncherDrawer(
                modules: [FoodDecisionModule.descriptor],
                openModule: $open,
                startsOpen: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .background(Theme.duskGradient)
        }
    }
    return Host()
}
```

- [ ] **Step 2: Implement `OurApp/Core/Shell/ModuleHostView.swift`**

```swift
import SwiftUI

/// Full-screen container the shell mounts a module in. Adds only a floating
/// glass close button — the module inside stays completely untouched
/// (module contract: the shell never reaches past the entry view).
struct ModuleHostView: View {
    let module: ModuleDescriptor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        module.makeEntryView()
            .overlay(alignment: .topTrailing) {
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                        .padding(11)
                }
                .glassCard(cornerRadius: 22)
                .padding(.trailing, 16)
                .accessibilityLabel(Text("Close"))
            }
    }
}

#Preview {
    ModuleHostView(module: FoodDecisionModule.descriptor)
}
```

- [ ] **Step 3: Verify build + suite**

Run: the full suite command. Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Add module launcher drawer and full-screen module host"
```

---

### Task 8: CouplesHomeView composition + shell wiring + simulator verification

**Files:**
- Create: `OurApp/Core/Shell/CouplesHomeView.swift`
- Modify: `OurApp/App/AppShell.swift` (replace body)

**Interfaces:**
- Consumes: everything from Tasks 2–7.
- Produces: `CouplesHomeView(modules: [ModuleDescriptor])`; `AppShell` now renders it with `[FoodDecisionModule.descriptor]`.

- [ ] **Step 1: Implement `OurApp/Core/Shell/CouplesHomeView.swift`**

```swift
import SwiftUI

/// The themed couples home (decision P4): dreamy background, the two of us,
/// the together counter, and the launcher drawer. DEBUG launch arguments
/// `-openDrawer` / `-openSettings` exist solely so headless screenshot
/// verification can reach those states (simctl can't tap).
struct CouplesHomeView: View {
    let modules: [ModuleDescriptor]

    @State private var identity = CoupleIdentityStore()
    @State private var tilt = TiltModel()
    @State private var openModule: ModuleDescriptor?
    @State private var showSettings = false

    var body: some View {
        ZStack {
            DreamyBackground(parallax: tilt.offset)

            VStack(spacing: 26) {
                Spacer(minLength: 70)
                PartnerAvatarsView(identity: identity)
                    .offset(x: tilt.offset.width * 0.4, y: tilt.offset.height * 0.4)

                if let anniversary = identity.anniversary {
                    TogetherCounterView(anniversary: anniversary)
                } else {
                    Button {
                        showSettings = true
                    } label: {
                        Label {
                            Text("Set your anniversary")
                        } icon: {
                            Image(systemName: "heart.circle.fill")
                        }
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                    .glassCard(cornerRadius: 22)
                }

                if identity.nameOne.isEmpty && identity.nameTwo.isEmpty {
                    Button {
                        showSettings = true
                    } label: {
                        Text("Add your names")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                Spacer()
                ModuleLauncherDrawer(
                    modules: modules,
                    openModule: $openModule,
                    startsOpen: launchArguments.contains("-openDrawer")
                )
            }
            .padding(.bottom, 10)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                Haptics.tap()
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(11)
            }
            .glassCard(cornerRadius: 22)
            .padding(.trailing, 16)
            .accessibilityLabel(Text("Our details"))
        }
        .fullScreenCover(item: $openModule) { module in
            ModuleHostView(module: module)
        }
        .sheet(isPresented: $showSettings) {
            CoupleSettingsSheet(identity: identity)
        }
        .onAppear {
            tilt.start()
            if launchArguments.contains("-openSettings") { showSettings = true }
        }
        .onDisappear { tilt.stop() }
    }

    private var launchArguments: [String] {
        #if DEBUG
        ProcessInfo.processInfo.arguments
        #else
        []
        #endif
    }
}

#Preview {
    CouplesHomeView(modules: [FoodDecisionModule.descriptor])
}
```

- [ ] **Step 2: Replace `OurApp/App/AppShell.swift` body**

```swift
import SwiftUI

/// The platform's mount point: the themed couples home (P4). Modules are
/// registered here — one line per module, nothing else crosses the seam.
struct AppShell: View {
    private let modules = [
        FoodDecisionModule.descriptor,
    ]

    var body: some View {
        CouplesHomeView(modules: modules)
    }
}

#Preview {
    AppShell()
}
```

- [ ] **Step 3: Full suite**

Run: the full suite command. Expected: PASS (all suites incl. Localization, CoupleIdentity, ModuleDescriptor).

- [ ] **Step 4: Simulator verification (screenshots)**

```bash
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
xcodebuild build -project OurApp.xcodeproj -scheme OurApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build -quiet
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/OurApp.app
SCRATCH=/private/tmp/claude-501/-Users-meixiaobin-Desktop-Our-App/814bea34-874e-4648-9367-b630a0384bc0/scratchpad
xcrun simctl launch booted com.ourapp.OurApp; sleep 4
xcrun simctl io booted screenshot "$SCRATCH/shell-home.png"
xcrun simctl terminate booted com.ourapp.OurApp
xcrun simctl launch booted com.ourapp.OurApp -openDrawer; sleep 4
xcrun simctl io booted screenshot "$SCRATCH/shell-drawer.png"
xcrun simctl terminate booted com.ourapp.OurApp
# zh-Hans run proves localization end-to-end:
xcrun simctl launch booted com.ourapp.OurApp -openDrawer -AppleLanguages "(zh-Hans)" -AppleLocale zh_CN; sleep 4
xcrun simctl io booted screenshot "$SCRATCH/shell-drawer-zh.png"
```

Then **Read all three screenshots** and confirm: home shows gradient background + avatar circles + "Set your anniversary" glass pill + closed drawer; drawer shot shows the 🍽️ "What should we eat?" tile; zh shot shows 我们的空间 / 吃点什么好？/ 设置纪念日. Describe what you see in the report.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add themed couples home and mount module launcher in app shell"
```

---

### Task 9: Docs decision-log check + PR

**Files:**
- Modify: `docs/DESIGN.md` only if a real fork got decided mid-build (P4–P7 already exist from the docs commit; most builds of this plan need no doc change).

- [ ] **Step 1: Verify docs**

Re-read `docs/DESIGN.md` §4/§5: confirm the built shell matches (themed shell, launcher, P4–P7). If an implementation deviation was ruled during review, append the row; otherwise no edit.

- [ ] **Step 2: Final full suite**

Run: the full suite command. Expected: PASS.

- [ ] **Step 3: Push and raise the PR (controller does this)**

PR must follow `.github/pull_request_template.md`: Description (this milestone per DESIGN.md §4), Solution (file structure + P4–P7), Testing (suite command + count), Proof of Testing (the three screenshots — note their scratchpad paths for the human to drag into the PR, since the CLI can't upload images).
