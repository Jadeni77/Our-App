# Food Decision v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the full Food Decision module v1 — propose a cuisine (random or typed) → agree/re-roll → decided → nearby restaurants via MapKit — with silent SwiftData history, in a fresh hand-written Xcode project.

**Architecture:** A thin app shell mounts the self-contained FoodDecision module. An `@Observable` state machine (`FoodDecisionFlow`) drives three phase views; MapKit hides behind a `RestaurantProvider` protocol; completed decisions persist silently through the core's SwiftData container. Spec: `docs/superpowers/specs/2026-07-28-food-decision-v1-design.md`.

**Tech Stack:** Swift (language mode 5), SwiftUI, SwiftData, MapKit, CoreLocation, Swift Testing (unit tests). No third-party dependencies, no code-signing team (simulator only).

## Global Constraints

- Working directory: `/Users/meixiaobin/Desktop/Our-App` (git repo on `main`).
- iOS deployment target: **17.0**. Build/test with Xcode 26.2 on the **iPhone 17 Pro** simulator.
- Bundle IDs: app `com.ourapp.OurApp`, tests `com.ourapp.OurAppTests`. Product name `OurApp`.
- $0 rule: no paid APIs, no Apple developer team, no Homebrew installs, no packages.
- Module contract: FoodDecision code lives under `OurApp/Modules/FoodDecision/`, never imports other modules, touches persistence only via the injected SwiftData context, and hides MapKit behind `RestaurantProvider`.
- **Commit messages: plain imperative English. NO AI attribution of any kind** (no `Co-Authored-By: Claude`, no "Generated with" footers) — hard user requirement.
- The `.xcodeproj` uses synchronized folder groups: **new source files are picked up automatically; never edit `project.pbxproj` to add files.**
- Full test suite command (used by several tasks):
  `xcodebuild test -project OurApp.xcodeproj -scheme OurApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
  (First run may spend a minute booting the simulator; that's normal. Scope with `-only-testing:OurAppTests/<SuiteName>` for fast TDD loops.)

---

### Task 1: Xcode project scaffold + walking skeleton

Hand-written minimal project: two targets (app + unit tests) pointing at synchronized folders, a shared scheme so `xcodebuild` works headlessly, a placeholder app, and one smoke test proving the whole build/test harness runs.

**Files:**
- Create: `.gitignore`
- Create: `OurApp.xcodeproj/project.pbxproj`
- Create: `OurApp.xcodeproj/xcshareddata/xcschemes/OurApp.xcscheme`
- Create: `OurApp/App/OurAppApp.swift`
- Create: `OurApp/App/AppShell.swift`
- Create: `OurAppTests/SmokeTests.swift`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: a buildable/testable project. `AppShell` (SwiftUI `View`) is the module mount point later tasks modify. Targets: `OurApp` (app), `OurAppTests` (unit test bundle, `@testable import OurApp` works — `ENABLE_TESTABILITY = YES` in Debug).

- [ ] **Step 1: Write `.gitignore`**

```gitignore
.DS_Store
xcuserdata/
DerivedData/
build/
*.xcuserstate
```

- [ ] **Step 2: Write `OurApp.xcodeproj/project.pbxproj`**

Fixed 24-hex-char object IDs are used throughout (`0A…01`–`0A…19`); the scheme file in Step 3 references the two target IDs, so don't change them.

```pbxproj
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 77;
	objects = {

/* Begin PBXContainerItemProxy section */
		0A0000000000000000000018 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = 0A0000000000000000000001 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = 0A0000000000000000000006;
			remoteInfo = OurApp;
		};
/* End PBXContainerItemProxy section */

/* Begin PBXFileReference section */
		0A0000000000000000000008 /* OurApp.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = OurApp.app; sourceTree = BUILT_PRODUCTS_DIR; };
		0A0000000000000000000009 /* OurAppTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = OurAppTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		0A0000000000000000000004 /* OurApp */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = OurApp;
			sourceTree = "<group>";
		};
		0A0000000000000000000005 /* OurAppTests */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = OurAppTests;
			sourceTree = "<group>";
		};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		0A000000000000000000000B /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		0A000000000000000000000E /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		0A0000000000000000000002 = {
			isa = PBXGroup;
			children = (
				0A0000000000000000000004 /* OurApp */,
				0A0000000000000000000005 /* OurAppTests */,
				0A0000000000000000000003 /* Products */,
			);
			sourceTree = "<group>";
		};
		0A0000000000000000000003 /* Products */ = {
			isa = PBXGroup;
			children = (
				0A0000000000000000000008 /* OurApp.app */,
				0A0000000000000000000009 /* OurAppTests.xctest */,
			);
			name = Products;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		0A0000000000000000000006 /* OurApp */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 0A0000000000000000000010 /* Build configuration list for PBXNativeTarget "OurApp" */;
			buildPhases = (
				0A000000000000000000000A /* Sources */,
				0A000000000000000000000B /* Frameworks */,
				0A000000000000000000000C /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				0A0000000000000000000004 /* OurApp */,
			);
			name = OurApp;
			packageProductDependencies = (
			);
			productName = OurApp;
			productReference = 0A0000000000000000000008 /* OurApp.app */;
			productType = "com.apple.product-type.application";
		};
		0A0000000000000000000007 /* OurAppTests */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 0A0000000000000000000011 /* Build configuration list for PBXNativeTarget "OurAppTests" */;
			buildPhases = (
				0A000000000000000000000D /* Sources */,
				0A000000000000000000000E /* Frameworks */,
			);
			buildRules = (
			);
			dependencies = (
				0A0000000000000000000019 /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				0A0000000000000000000005 /* OurAppTests */,
			);
			name = OurAppTests;
			packageProductDependencies = (
			);
			productName = OurAppTests;
			productReference = 0A0000000000000000000009 /* OurAppTests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		0A0000000000000000000001 /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 2620;
				LastUpgradeCheck = 2620;
				TargetAttributes = {
					0A0000000000000000000007 = {
						TestTargetID = 0A0000000000000000000006;
					};
				};
			};
			buildConfigurationList = 0A000000000000000000000F /* Build configuration list for PBXProject "OurApp" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = 0A0000000000000000000002;
			minimizedProjectReferenceProxies = 1;
			preferredProjectObjectVersion = 77;
			productRefGroup = 0A0000000000000000000003 /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				0A0000000000000000000006 /* OurApp */,
				0A0000000000000000000007 /* OurAppTests */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		0A000000000000000000000C /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		0A000000000000000000000A /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		0A000000000000000000000D /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		0A0000000000000000000019 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = 0A0000000000000000000006 /* OurApp */;
			targetProxy = 0A0000000000000000000018 /* PBXContainerItemProxy */;
		};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
		0A0000000000000000000012 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				MTL_FAST_MATH = YES;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = iphoneos;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.0;
			};
			name = Debug;
		};
		0A0000000000000000000013 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_NO_COMMON_BLOCKS = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
				MTL_ENABLE_DEBUG_INFO = NO;
				MTL_FAST_MATH = YES;
				SDKROOT = iphoneos;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
				SWIFT_VERSION = 5.0;
				VALIDATE_PRODUCT = YES;
			};
			name = Release;
		};
		0A0000000000000000000014 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_NSLocationWhenInUseUsageDescription = "We use your location to find restaurants near you.";
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.ourapp.OurApp;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				TARGETED_DEVICE_FAMILY = 1;
			};
			name = Debug;
		};
		0A0000000000000000000015 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_NSLocationWhenInUseUsageDescription = "We use your location to find restaurants near you.";
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.ourapp.OurApp;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				TARGETED_DEVICE_FAMILY = 1;
			};
			name = Release;
		};
		0A0000000000000000000016 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.ourapp.OurAppTests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = NO;
				TARGETED_DEVICE_FAMILY = 1;
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/OurApp.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/OurApp";
			};
			name = Debug;
		};
		0A0000000000000000000017 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.ourapp.OurAppTests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = NO;
				TARGETED_DEVICE_FAMILY = 1;
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/OurApp.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/OurApp";
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		0A000000000000000000000F /* Build configuration list for PBXProject "OurApp" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				0A0000000000000000000012 /* Debug */,
				0A0000000000000000000013 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		0A0000000000000000000010 /* Build configuration list for PBXNativeTarget "OurApp" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				0A0000000000000000000014 /* Debug */,
				0A0000000000000000000015 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		0A0000000000000000000011 /* Build configuration list for PBXNativeTarget "OurAppTests" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				0A0000000000000000000016 /* Debug */,
				0A0000000000000000000017 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */
	};
	rootObject = 0A0000000000000000000001 /* Project object */;
}
```

- [ ] **Step 3: Write the shared scheme `OurApp.xcodeproj/xcshareddata/xcschemes/OurApp.xcscheme`**

Without a shared scheme, headless `xcodebuild -scheme` fails (Xcode only auto-creates schemes in the GUI).

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2620"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "0A0000000000000000000006"
               BuildableName = "OurApp.app"
               BlueprintName = "OurApp"
               ReferencedContainer = "container:OurApp.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "0A0000000000000000000007"
               BuildableName = "OurAppTests.xctest"
               BlueprintName = "OurAppTests"
               ReferencedContainer = "container:OurApp.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "0A0000000000000000000006"
            BuildableName = "OurApp.app"
            BlueprintName = "OurApp"
            ReferencedContainer = "container:OurApp.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
```

- [ ] **Step 4: Write the placeholder app**

`OurApp/App/OurAppApp.swift`:

```swift
import SwiftUI

@main
struct OurAppApp: App {
    var body: some Scene {
        WindowGroup {
            AppShell()
        }
    }
}
```

`OurApp/App/AppShell.swift`:

```swift
import SwiftUI

/// The platform's module mount point. Today it mounts the only module directly;
/// when module #2 arrives this becomes a switcher (TabView or similar).
struct AppShell: View {
    var body: some View {
        Text("OurApp")
            .font(.largeTitle)
    }
}

#Preview {
    AppShell()
}
```

- [ ] **Step 5: Write the smoke test `OurAppTests/SmokeTests.swift`**

```swift
import Testing
@testable import OurApp

struct SmokeTests {
    @Test func harnessRuns() {
        #expect(Bool(true))
    }
}
```

- [ ] **Step 6: Verify the project builds**

Run: `xcodebuild build -project OurApp.xcodeproj -scheme OurApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: exits 0 (warnings OK, no errors). If it fails parsing the pbxproj, fix the pbxproj — do not switch scaffolding approaches.

- [ ] **Step 7: Verify the test harness runs**

Run: `xcodebuild test -project OurApp.xcodeproj -scheme OurApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: exits 0, output contains `Test Suite 'All tests' passed` / `** TEST SUCCEEDED **` with 1 test.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Scaffold OurApp Xcode project with app and test targets"
```

---

### Task 2: DecisionRecord model + core Persistence factory

**Files:**
- Create: `OurApp/Modules/FoodDecision/DecisionRecord.swift`
- Create: `OurApp/Core/Persistence.swift`
- Modify: `OurApp/App/OurAppApp.swift`
- Test: `OurAppTests/PersistenceTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `@Model final class DecisionRecord { var date: Date; var cuisineChosen: String; init(date: Date = .now, cuisineChosen: String) }` and `enum Persistence { static func makeContainer(inMemory: Bool = false) throws -> ModelContainer }`. The app attaches the container via `.modelContainer(...)`, so `@Environment(\.modelContext)` works in every view.

- [ ] **Step 1: Write the failing test `OurAppTests/PersistenceTests.swift`**

```swift
import Testing
import SwiftData
@testable import OurApp

struct PersistenceTests {
    @Test func savesAndFetchesDecisionRecords() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = ModelContext(container)

        context.insert(DecisionRecord(cuisineChosen: "Hotpot"))
        try context.save()

        let records = try context.fetch(FetchDescriptor<DecisionRecord>())
        #expect(records.count == 1)
        #expect(records.first?.cuisineChosen == "Hotpot")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project OurApp.xcodeproj -scheme OurApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OurAppTests/PersistenceTests -quiet`
Expected: FAIL — compile error `cannot find 'Persistence' in scope` / `cannot find 'DecisionRecord' in scope`.

- [ ] **Step 3: Implement the model and factory**

`OurApp/Modules/FoodDecision/DecisionRecord.swift`:

```swift
import Foundation
import SwiftData

/// One completed decision, recorded silently on every Agree (decision F4).
/// No UI reads this in v1 — it seeds the future history module and smarter picks.
@Model
final class DecisionRecord {
    var date: Date
    var cuisineChosen: String

    init(date: Date = .now, cuisineChosen: String) {
        self.date = date
        self.cuisineChosen = cuisineChosen
    }
}
```

`OurApp/Core/Persistence.swift`:

```swift
import Foundation
import SwiftData

/// Core persistence: the one place the app assembles its SwiftData container.
/// Modules contribute their @Model types to the schema here — they never build
/// their own containers.
enum Persistence {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            DecisionRecord.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
```

Replace `OurApp/App/OurAppApp.swift` entirely with:

```swift
import SwiftUI
import SwiftData

@main
struct OurAppApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try Persistence.makeContainer()
        } catch {
            // Cannot run without local storage; crashing at launch beats silent data loss.
            fatalError("Failed to create model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppShell()
        }
        .modelContainer(container)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same command as Step 2.
Expected: PASS (`** TEST SUCCEEDED **`).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add DecisionRecord model and core SwiftData persistence factory"
```

---

### Task 3: Cuisine value type + built-in pool

**Files:**
- Create: `OurApp/Modules/FoodDecision/CuisinePool.swift`
- Test: `OurAppTests/CuisinePoolTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `struct Cuisine: Equatable, Hashable { let name: String; let emoji: String }` and `enum CuisinePool { static let all: [Cuisine]; static func draw(excluding: Cuisine? = nil) -> Cuisine }`. The pool includes `Cuisine(name: "Hotpot", emoji: "🍲")` and `Cuisine(name: "Ramen", emoji: "🍜")` — Task 4's tests rely on those two exact entries.

- [ ] **Step 1: Write the failing test `OurAppTests/CuisinePoolTests.swift`**

```swift
import Testing
@testable import OurApp

struct CuisinePoolTests {
    @Test func poolHasThirtyToFortyUniqueEntries() {
        #expect(CuisinePool.all.count >= 30)
        #expect(CuisinePool.all.count <= 40)
        #expect(Set(CuisinePool.all.map(\.name)).count == CuisinePool.all.count)
    }

    @Test func drawReturnsAPoolMember() {
        #expect(CuisinePool.all.contains(CuisinePool.draw()))
    }

    @Test func drawNeverReturnsTheExcludedCuisine() {
        let excluded = CuisinePool.all[0]
        for _ in 0..<200 {
            #expect(CuisinePool.draw(excluding: excluded) != excluded)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project OurApp.xcodeproj -scheme OurApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OurAppTests/CuisinePoolTests -quiet`
Expected: FAIL — compile error `cannot find 'CuisinePool' in scope`.

- [ ] **Step 3: Implement `OurApp/Modules/FoodDecision/CuisinePool.swift`**

```swift
import Foundation

/// A cuisine/flavor proposal. Manual entries get the fallback fork-and-knife emoji.
struct Cuisine: Equatable, Hashable {
    let name: String
    let emoji: String
}

/// The built-in pool — the one editable place to tweak what the dice can roll.
enum CuisinePool {
    static let all: [Cuisine] = [
        Cuisine(name: "Hotpot", emoji: "🍲"),
        Cuisine(name: "Sichuan", emoji: "🌶️"),
        Cuisine(name: "Cantonese", emoji: "🦆"),
        Cuisine(name: "Dim Sum", emoji: "🥟"),
        Cuisine(name: "Dumplings", emoji: "🥟"),
        Cuisine(name: "Malatang", emoji: "🍢"),
        Cuisine(name: "Hand-pulled Noodles", emoji: "🍜"),
        Cuisine(name: "Congee", emoji: "🥣"),
        Cuisine(name: "Taiwanese", emoji: "🍱"),
        Cuisine(name: "Ramen", emoji: "🍜"),
        Cuisine(name: "Sushi", emoji: "🍣"),
        Cuisine(name: "Udon", emoji: "🍜"),
        Cuisine(name: "Tonkatsu", emoji: "🍱"),
        Cuisine(name: "Japanese Curry", emoji: "🍛"),
        Cuisine(name: "Izakaya", emoji: "🍶"),
        Cuisine(name: "Korean BBQ", emoji: "🥩"),
        Cuisine(name: "Bibimbap", emoji: "🍚"),
        Cuisine(name: "Korean Fried Chicken", emoji: "🍗"),
        Cuisine(name: "Pho", emoji: "🍜"),
        Cuisine(name: "Banh Mi", emoji: "🥖"),
        Cuisine(name: "Thai", emoji: "🍛"),
        Cuisine(name: "Indian", emoji: "🍛"),
        Cuisine(name: "Pizza", emoji: "🍕"),
        Cuisine(name: "Pasta", emoji: "🍝"),
        Cuisine(name: "Burgers", emoji: "🍔"),
        Cuisine(name: "Sandwiches", emoji: "🥪"),
        Cuisine(name: "Fried Chicken", emoji: "🍗"),
        Cuisine(name: "American BBQ", emoji: "🍖"),
        Cuisine(name: "Steakhouse", emoji: "🥩"),
        Cuisine(name: "Seafood", emoji: "🦞"),
        Cuisine(name: "Lobster Roll", emoji: "🦞"),
        Cuisine(name: "Tacos", emoji: "🌮"),
        Cuisine(name: "Burritos", emoji: "🌯"),
        Cuisine(name: "Shawarma", emoji: "🌯"),
        Cuisine(name: "Falafel", emoji: "🧆"),
        Cuisine(name: "Mediterranean", emoji: "🥙"),
        Cuisine(name: "Greek", emoji: "🥗"),
        Cuisine(name: "Poke", emoji: "🥗"),
        Cuisine(name: "Brunch", emoji: "🥞"),
    ]

    /// Purely random draw (open question resolved for v1: no history bias yet).
    /// Excluding the current proposal keeps a re-roll from repeating itself.
    static func draw(excluding excluded: Cuisine? = nil) -> Cuisine {
        let candidates = all.filter { $0 != excluded }
        return candidates.randomElement() ?? all[0]
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add cuisine pool with random draw"
```

---

### Task 4: FoodDecisionFlow state machine

**Files:**
- Create: `OurApp/Modules/FoodDecision/FoodDecisionFlow.swift`
- Test: `OurAppTests/FoodDecisionFlowTests.swift`

**Interfaces:**
- Consumes: `Cuisine`, `CuisinePool.draw(excluding:)` (Task 3); `DecisionRecord`, `Persistence.makeContainer(inMemory:)` (Task 2).
- Produces:
  ```swift
  @MainActor @Observable final class FoodDecisionFlow {
      enum Phase: Equatable { case propose; case deciding(Cuisine); case decided(Cuisine) }
      private(set) var phase: Phase   // starts .propose
      init()
      func proposeRandom()
      func proposeManual(_ text: String)   // trims; blank input is a no-op
      func reroll()                        // only in .deciding
      func agree(in context: ModelContext) // persists DecisionRecord, → .decided
      func startOver()                     // → .propose
  }
  ```
  Task 8's views call exactly these members.

- [ ] **Step 1: Write the failing test `OurAppTests/FoodDecisionFlowTests.swift`**

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

    @Test func proposeManualTrimsAndUsesFallbackEmoji() {
        let flow = FoodDecisionFlow()
        flow.proposeManual("  Xinjiang BBQ  ")
        #expect(flow.phase == .deciding(Cuisine(name: "Xinjiang BBQ", emoji: "🍽️")))
    }

    @Test func proposeManualMatchesPoolEntryCaseInsensitively() {
        let flow = FoodDecisionFlow()
        flow.proposeManual("hotpot")
        #expect(flow.phase == .deciding(Cuisine(name: "Hotpot", emoji: "🍲")))
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

    @Test func agreePersistsARecordAndMovesToDecided() throws {
        let context = try makeContext()
        let flow = FoodDecisionFlow()
        flow.proposeManual("Ramen")
        flow.agree(in: context)

        #expect(flow.phase == .decided(Cuisine(name: "Ramen", emoji: "🍜")))
        let records = try context.fetch(FetchDescriptor<DecisionRecord>())
        #expect(records.map(\.cuisineChosen) == ["Ramen"])
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

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project OurApp.xcodeproj -scheme OurApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OurAppTests/FoodDecisionFlowTests -quiet`
Expected: FAIL — compile error `cannot find 'FoodDecisionFlow' in scope`.

- [ ] **Step 3: Implement `OurApp/Modules/FoodDecision/FoodDecisionFlow.swift`**

```swift
import Foundation
import Observation
import SwiftData

/// The decide-together state machine: propose → deciding → decided.
/// Pure logic, no UI — views render `phase` and call the transitions.
@MainActor
@Observable
final class FoodDecisionFlow {
    enum Phase: Equatable {
        case propose
        case deciding(Cuisine)
        case decided(Cuisine)
    }

    private(set) var phase: Phase = .propose

    func proposeRandom() {
        phase = .deciding(CuisinePool.draw())
    }

    /// Manual entry. Matches a pool entry case-insensitively (to reuse its emoji);
    /// unknown cuisines get the fallback emoji. Blank input is ignored.
    func proposeManual(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let cuisine = CuisinePool.all.first { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
            ?? Cuisine(name: trimmed, emoji: "🍽️")
        phase = .deciding(cuisine)
    }

    func reroll() {
        guard case .deciding(let current) = phase else { return }
        phase = .deciding(CuisinePool.draw(excluding: current))
    }

    /// Agree seals the decision and silently records it (decision F4).
    /// The context comes from the view layer so the flow stays construction-free in tests.
    func agree(in context: ModelContext) {
        guard case .deciding(let cuisine) = phase else { return }
        context.insert(DecisionRecord(cuisineChosen: cuisine.name))
        try? context.save()
        phase = .decided(cuisine)
    }

    func startOver() {
        phase = .propose
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same command as Step 2.
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add FoodDecisionFlow state machine with silent decision recording"
```

---

### Task 5: Restaurant model, provider protocol, MapKit result mapping

**Files:**
- Create: `OurApp/Modules/FoodDecision/RestaurantProvider.swift`
- Create: `OurApp/Modules/FoodDecision/MapKitRestaurantProvider.swift` (mapping only; live search arrives in Task 6)
- Test: `OurAppTests/RestaurantMappingTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  ```swift
  struct Restaurant: Identifiable, Equatable {
      let id: UUID
      let name: String
      let distanceMeters: Double
      let address: String?
      let phone: String?
      let latitude: Double
      let longitude: Double
  }
  enum RestaurantSearchError: Error, Equatable { case locationDenied, noResults, searchFailed }
  protocol RestaurantProvider {
      @MainActor func search(cuisine: String) async throws -> [Restaurant]
  }
  struct MapKitRestaurantProvider {
      static func restaurants(from mapItems: [MKMapItem], userLocation: CLLocation, limit: Int = 8) -> [Restaurant]
  }
  ```
  Non-obvious bit: the protocol method is `@MainActor` on purpose — search is always UI-triggered, and this sidesteps actor-isolation friction with `CLLocationManager` (whose delegate callbacks want main-thread affinity) without any `Sendable` gymnastics.

- [ ] **Step 1: Write the failing test `OurAppTests/RestaurantMappingTests.swift`**

```swift
import Testing
import MapKit
@testable import OurApp

struct RestaurantMappingTests {
    // Northeastern-ish Boston coordinates.
    private let userLocation = CLLocation(latitude: 42.3398, longitude: -71.0892)

    private func mapItem(name: String, latitude: Double, longitude: Double) -> MKMapItem {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        let item = MKMapItem(placemark: placemark)
        item.name = name
        return item
    }

    @Test func computesDistanceFromUserLocation() {
        // 0.01° of latitude ≈ 1112 m.
        let items = [mapItem(name: "Far Bowl", latitude: 42.3498, longitude: -71.0892)]
        let result = MapKitRestaurantProvider.restaurants(from: items, userLocation: userLocation)
        #expect(result.count == 1)
        #expect(abs(result[0].distanceMeters - 1112) < 25)
    }

    @Test func sortsByDistanceFromUser() {
        let items = [
            mapItem(name: "Far Bowl", latitude: 42.3598, longitude: -71.0892),
            mapItem(name: "Near Noodles", latitude: 42.3408, longitude: -71.0892),
        ]
        let result = MapKitRestaurantProvider.restaurants(from: items, userLocation: userLocation)
        #expect(result.map(\.name) == ["Near Noodles", "Far Bowl"])
    }

    @Test func capsResultsAtTheLimit() {
        let items = (0..<12).map { index in
            mapItem(name: "Spot \(index)", latitude: 42.3398 + Double(index) * 0.001, longitude: -71.0892)
        }
        let result = MapKitRestaurantProvider.restaurants(from: items, userLocation: userLocation)
        #expect(result.count == 8)
    }

    @Test func fallsBackToPlaceholderNameAndKeepsCoordinates() {
        // Empty string, not nil: MapKit synthesizes a placeholder name for
        // coordinate-only items, so a nil name can't occur with real items.
        // (Amended 2026-07-28 by human ruling during Task 5 review.)
        let items = [mapItem(name: "", latitude: 42.3408, longitude: -71.0902)]
        let result = MapKitRestaurantProvider.restaurants(from: items, userLocation: userLocation)
        #expect(result[0].name == "Unnamed spot")
        #expect(abs(result[0].latitude - 42.3408) < 0.0001)
        #expect(abs(result[0].longitude - -71.0902) < 0.0001)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project OurApp.xcodeproj -scheme OurApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OurAppTests/RestaurantMappingTests -quiet`
Expected: FAIL — compile error `cannot find 'MapKitRestaurantProvider' in scope`.

- [ ] **Step 3: Implement the two source files**

`OurApp/Modules/FoodDecision/RestaurantProvider.swift`:

```swift
import Foundation

/// One nearby restaurant, already distance-annotated relative to the user.
/// Deliberately MapKit-free so the provider stays swappable (module contract).
struct Restaurant: Identifiable, Equatable {
    let id: UUID
    let name: String
    let distanceMeters: Double
    let address: String?
    let phone: String?
    let latitude: Double
    let longitude: Double
}

enum RestaurantSearchError: Error, Equatable {
    case locationDenied
    case noResults
    case searchFailed
}

/// The module's seam for restaurant lookup (decision F3 hides MapKit behind this).
/// @MainActor because search is always UI-triggered and the CoreLocation machinery
/// underneath wants main-thread affinity — this keeps implementations warning-free.
protocol RestaurantProvider {
    @MainActor func search(cuisine: String) async throws -> [Restaurant]
}
```

`OurApp/Modules/FoodDecision/MapKitRestaurantProvider.swift`:

```swift
import Foundation
import MapKit

/// MapKit-backed implementation of `RestaurantProvider` (decision F3: free,
/// native, no API key). Task 6 adds the live `search`; the mapping below is
/// pure and unit-tested.
struct MapKitRestaurantProvider {
    /// Converts raw MapKit results into distance-sorted, capped `Restaurant`s.
    static func restaurants(
        from mapItems: [MKMapItem],
        userLocation: CLLocation,
        limit: Int = 8
    ) -> [Restaurant] {
        let mapped = mapItems.map { item in
            let coordinate = item.placemark.coordinate
            let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .distance(from: userLocation)
            // MapKit synthesizes a name for coordinate-only items, so nil is
            // defensive; the empty check is the realistic missing-name path.
            // (Amended 2026-07-28 by human ruling during Task 5 review.)
            let name = item.name.flatMap { $0.isEmpty ? nil : $0 } ?? "Unnamed spot"
            return Restaurant(
                id: UUID(),
                name: name,
                distanceMeters: distance,
                address: item.placemark.title,
                phone: item.phoneNumber,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        }
        return Array(mapped.sorted { $0.distanceMeters < $1.distanceMeters }.prefix(limit))
    }
}
```

Note: `item.placemark` and `MKMapItem(placemark:)` emit deprecation *warnings* under the iOS 26 SDK. That's expected and fine — the deployment target is 17.0 and the replacements (`MKMapItem.address`/`.location`) don't exist there. Do not chase these warnings.

- [ ] **Step 4: Run test to verify it passes**

Run: same command as Step 2.
Expected: PASS (4 tests). If `name = ""` behaves oddly: setting `unnamed[0].name = nil` is the case under test; `MKMapItem.name` is optional-settable.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add Restaurant model, provider protocol, and MapKit result mapping"
```

---

### Task 6: LocationFetcher + live MKLocalSearch

Live-service code (CoreLocation prompt, network search) — verified by compilation here and exercised for real in Task 9's simulator run. No unit tests for this task by design: everything testable was extracted into Task 5's pure mapping.

**Files:**
- Create: `OurApp/Modules/FoodDecision/LocationFetcher.swift`
- Modify: `OurApp/Modules/FoodDecision/MapKitRestaurantProvider.swift` (append the extension at the end of the file)

**Interfaces:**
- Consumes: `Restaurant`, `RestaurantSearchError`, `RestaurantProvider`, `MapKitRestaurantProvider.restaurants(from:userLocation:limit:)` (Task 5).
- Produces: `MapKitRestaurantProvider: RestaurantProvider` conformance (`init()` is the free memberwise/default one) and `@MainActor final class LocationFetcher { func currentLocation() async throws -> CLLocation }` which throws `RestaurantSearchError.locationDenied` / `.searchFailed`.

- [ ] **Step 1: Implement `OurApp/Modules/FoodDecision/LocationFetcher.swift`**

```swift
import CoreLocation

/// One-shot async wrapper around CLLocationManager: request permission if
/// needed, then fetch a single current location.
///
/// Non-obvious bits:
/// - `locationManagerDidChangeAuthorization` also fires when the delegate is
///   first attached; the `.notDetermined` guard ignores that initial callback.
/// - The caller keeps this object alive across the awaits (a local `let` in an
///   async function is enough) — CLLocationManager holds its delegate weakly.
@MainActor
final class LocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    func currentLocation() async throws -> CLLocation {
        manager.delegate = self

        var status = manager.authorizationStatus
        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                authorizationContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        }
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            throw RestaurantSearchError.locationDenied
        }

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard status != .notDetermined else { return }
            authorizationContinuation?.resume(returning: status)
            authorizationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        Task { @MainActor in
            locationContinuation?.resume(returning: location)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(throwing: RestaurantSearchError.searchFailed)
            locationContinuation = nil
        }
    }
}
```

- [ ] **Step 2: Append the live search to `MapKitRestaurantProvider.swift`**

Add at the end of the file:

```swift
extension MapKitRestaurantProvider: RestaurantProvider {
    /// Fixed ~5 km region, capped at 8 results (open question resolved for v1;
    /// adaptive radius deferred until real use demands it).
    /// @MainActor matches the protocol requirement — without it this witness is
    /// nonisolated and calling the @MainActor `LocationFetcher()` init won't compile.
    @MainActor
    func search(cuisine: String) async throws -> [Restaurant] {
        let fetcher = LocationFetcher()
        let userLocation = try await fetcher.currentLocation()

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = cuisine
        request.resultTypes = .pointOfInterest
        // Food-adjacent categories included so pool entries like Brunch, Banh Mi,
        // and Dim Sum (tagged cafe/bakery/market by MapKit) don't false-negative.
        // (Amended 2026-07-28 by human ruling during final review.)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket,
        ])
        request.region = MKCoordinateRegion(
            center: userLocation.coordinate,
            latitudinalMeters: 5_000,
            longitudinalMeters: 5_000
        )

        let response: MKLocalSearch.Response
        do {
            response = try await MKLocalSearch(request: request).start()
        } catch {
            // MKLocalSearch reports "no results" as an MKError; treat anything
            // else as a plain failure the UI can offer a retry for.
            if let mkError = error as? MKError, mkError.code == .placemarkNotFound {
                throw RestaurantSearchError.noResults
            }
            throw RestaurantSearchError.searchFailed
        }

        let restaurants = Self.restaurants(from: response.mapItems, userLocation: userLocation)
        guard !restaurants.isEmpty else { throw RestaurantSearchError.noResults }
        return restaurants
    }
}
```

- [ ] **Step 3: Verify everything still builds and existing tests pass**

Run: `xcodebuild test -project OurApp.xcodeproj -scheme OurApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: PASS — full suite (deprecation warnings about `placemark` are expected; errors are not).

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Add location fetcher and live MapKit restaurant search"
```

---

### Task 7: RestaurantSearch state model

**Files:**
- Create: `OurApp/Modules/FoodDecision/RestaurantSearch.swift`
- Test: `OurAppTests/RestaurantSearchTests.swift`

**Interfaces:**
- Consumes: `Cuisine` (Task 3); `Restaurant`, `RestaurantProvider`, `RestaurantSearchError` (Task 5); `MapKitRestaurantProvider()` (Task 6).
- Produces:
  ```swift
  @MainActor @Observable final class RestaurantSearch {
      enum State: Equatable { case loading; case loaded([Restaurant]); case locationDenied; case noResults; case failed }
      private(set) var state: State   // starts .loading
      let cuisine: Cuisine
      init(cuisine: Cuisine, provider: any RestaurantProvider = MapKitRestaurantProvider())
      func run() async
  }
  ```
  Task 9's `RestaurantListView` switches over exactly these five states.

- [ ] **Step 1: Write the failing test `OurAppTests/RestaurantSearchTests.swift`**

```swift
import Testing
import Foundation
@testable import OurApp

private struct MockProvider: RestaurantProvider {
    let result: Result<[Restaurant], Error>
    func search(cuisine: String) async throws -> [Restaurant] {
        try result.get()
    }
}

@MainActor
struct RestaurantSearchTests {
    private let cuisine = Cuisine(name: "Hotpot", emoji: "🍲")
    private let sample = [
        Restaurant(
            id: UUID(), name: "Haidilao", distanceMeters: 320,
            address: "1 Main St", phone: nil, latitude: 42.34, longitude: -71.08
        ),
    ]

    @Test func successLoadsRestaurants() async {
        let search = RestaurantSearch(cuisine: cuisine, provider: MockProvider(result: .success(sample)))
        await search.run()
        #expect(search.state == .loaded(sample))
    }

    @Test func locationDeniedMapsToDeniedState() async {
        let search = RestaurantSearch(
            cuisine: cuisine,
            provider: MockProvider(result: .failure(RestaurantSearchError.locationDenied))
        )
        await search.run()
        #expect(search.state == .locationDenied)
    }

    @Test func noResultsMapsToNoResultsState() async {
        let search = RestaurantSearch(
            cuisine: cuisine,
            provider: MockProvider(result: .failure(RestaurantSearchError.noResults))
        )
        await search.run()
        #expect(search.state == .noResults)
    }

    @Test func unexpectedErrorsMapToFailedState() async {
        let search = RestaurantSearch(
            cuisine: cuisine,
            provider: MockProvider(result: .failure(URLError(.notConnectedToInternet)))
        )
        await search.run()
        #expect(search.state == .failed)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project OurApp.xcodeproj -scheme OurApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OurAppTests/RestaurantSearchTests -quiet`
Expected: FAIL — compile error `cannot find 'RestaurantSearch' in scope`.

- [ ] **Step 3: Implement `OurApp/Modules/FoodDecision/RestaurantSearch.swift`**

```swift
import Foundation
import Observation

/// Drives one restaurant lookup and exposes a renderable state — every
/// failure degrades to a distinct, friendly state (fail-soft principle).
@MainActor
@Observable
final class RestaurantSearch {
    enum State: Equatable {
        case loading
        case loaded([Restaurant])
        case locationDenied
        case noResults
        case failed
    }

    private(set) var state: State = .loading
    let cuisine: Cuisine
    private let provider: any RestaurantProvider

    init(cuisine: Cuisine, provider: any RestaurantProvider = MapKitRestaurantProvider()) {
        self.cuisine = cuisine
        self.provider = provider
    }

    func run() async {
        state = .loading
        do {
            state = .loaded(try await provider.search(cuisine: cuisine.name))
        } catch RestaurantSearchError.locationDenied {
            state = .locationDenied
        } catch RestaurantSearchError.noResults {
            state = .noResults
        } catch {
            state = .failed
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same command as Step 2.
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add RestaurantSearch state model with fail-soft states"
```

---

### Task 8: Restaurant results UI (card list + directions + fail-soft states)

Pure UI on top of Task 7's states — verification is compilation plus the full suite (visual verification happens in Task 9's simulator run, where this screen is reached through the real flow).

**Files:**
- Create: `OurApp/Modules/FoodDecision/Views/RestaurantCard.swift`
- Create: `OurApp/Modules/FoodDecision/Views/RestaurantListView.swift`

**Interfaces:**
- Consumes: `Restaurant` (Task 5), `RestaurantSearch` + `State` (Task 7), `Cuisine` (Task 3), `MapKitRestaurantProvider` (Task 6, via the default argument).
- Produces: `RestaurantListView(cuisine: Cuisine)` — the screen Task 9's `DecidedView` pushes; `RestaurantCard(restaurant: Restaurant)`.

- [ ] **Step 1: Implement `OurApp/Modules/FoodDecision/Views/RestaurantCard.swift`**

```swift
import SwiftUI
import MapKit

struct RestaurantCard: View {
    let restaurant: Restaurant

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(restaurant.name)
                    .font(.headline)
                Spacer()
                Text(distanceText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let address = restaurant.address {
                Label(address, systemImage: "mappin.and.ellipse")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let phone = restaurant.phone {
                Label(phone, systemImage: "phone")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button(action: openDirections) {
                Label("Directions", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    /// Locale-aware road distance ("350 m" / "0.9 mi" depending on region).
    private var distanceText: String {
        Measurement(value: restaurant.distanceMeters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    private func openDirections() {
        let coordinate = CLLocationCoordinate2D(latitude: restaurant.latitude, longitude: restaurant.longitude)
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = restaurant.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

#Preview {
    RestaurantCard(restaurant: Restaurant(
        id: UUID(), name: "Haidilao Hot Pot", distanceMeters: 850,
        address: "40 Boylston St, Boston, MA", phone: "(617) 555-0123",
        latitude: 42.352, longitude: -71.064
    ))
    .padding()
}
```

- [ ] **Step 2: Implement `OurApp/Modules/FoodDecision/Views/RestaurantListView.swift`**

```swift
import SwiftUI
import UIKit

struct RestaurantListView: View {
    @State private var search: RestaurantSearch
    @Environment(\.openURL) private var openURL

    init(cuisine: Cuisine, provider: any RestaurantProvider = MapKitRestaurantProvider()) {
        _search = State(initialValue: RestaurantSearch(cuisine: cuisine, provider: provider))
    }

    var body: some View {
        Group {
            switch search.state {
            case .loading:
                ProgressView("Finding \(search.cuisine.name) near you…")
            case .loaded(let restaurants):
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(restaurants) { restaurant in
                            RestaurantCard(restaurant: restaurant)
                        }
                    }
                    .padding()
                }
            case .locationDenied:
                statusView(
                    emoji: "📍",
                    title: "We can't see where you are",
                    message: "Allow location access in Settings and we'll find \(search.cuisine.name) nearby."
                ) {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .noResults:
                statusView(
                    emoji: "🤷",
                    title: "Nothing nearby for \(search.cuisine.name)",
                    message: "Go back and try another cuisine — maybe re-roll?"
                ) {
                    EmptyView()
                }
            case .failed:
                statusView(
                    emoji: "😵",
                    title: "Search hiccuped",
                    message: "Check your connection and give it another go."
                ) {
                    Button("Retry") {
                        Task { await search.run() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("\(search.cuisine.emoji) \(search.cuisine.name)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await search.run() }
    }

    private func statusView(
        emoji: String,
        title: String,
        message: String,
        @ViewBuilder actions: () -> some View
    ) -> some View {
        VStack(spacing: 16) {
            Text(emoji).font(.system(size: 64))
            Text(title).font(.title3.bold())
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            actions()
        }
        .padding(32)
    }
}

#Preview {
    NavigationStack {
        RestaurantListView(cuisine: Cuisine(name: "Hotpot", emoji: "🍲"))
    }
}
```

- [ ] **Step 3: Verify build + full suite**

Run: `xcodebuild test -project OurApp.xcodeproj -scheme OurApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: PASS — everything compiles, all prior tests green.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Add restaurant results card list with directions and fail-soft states"
```

---

### Task 9: Flow views, module entry point, shell wiring + simulator verification

**Files:**
- Create: `OurApp/Modules/FoodDecision/Views/ProposeView.swift`
- Create: `OurApp/Modules/FoodDecision/Views/DecideView.swift`
- Create: `OurApp/Modules/FoodDecision/Views/DecidedView.swift`
- Create: `OurApp/Modules/FoodDecision/FoodDecisionModule.swift`
- Modify: `OurApp/App/AppShell.swift`

**Interfaces:**
- Consumes: `FoodDecisionFlow` + `Phase` (Task 4), `Cuisine` (Task 3), `RestaurantListView(cuisine:)` (Task 8), `@Environment(\.modelContext)` (container attached in Task 2).
- Produces: `FoodDecisionModuleView()` — the module's entry point per the module contract; `AppShell` now mounts it.

- [ ] **Step 1: Implement `OurApp/Modules/FoodDecision/Views/ProposeView.swift`**

```swift
import SwiftUI

struct ProposeView: View {
    let flow: FoodDecisionFlow
    @State private var manualEntry = ""

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            VStack(spacing: 12) {
                Text("🍽️").font(.system(size: 72))
                Text("What should we eat?")
                    .font(.largeTitle.bold())
                Text("Draw a cuisine, or type a craving.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 16) {
                Button {
                    flow.proposeRandom()
                } label: {
                    Label("Surprise us", systemImage: "dice.fill")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                HStack {
                    TextField("Or type a cuisine…", text: $manualEntry)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.go)
                        .onSubmit(submitManual)
                    Button("Go", action: submitManual)
                        .buttonStyle(.bordered)
                        .disabled(manualEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
    }

    private func submitManual() {
        flow.proposeManual(manualEntry)
        manualEntry = ""
    }
}

#Preview {
    ProposeView(flow: FoodDecisionFlow())
}
```

- [ ] **Step 2: Implement `OurApp/Modules/FoodDecision/Views/DecideView.swift`**

```swift
import SwiftUI

struct DecideView: View {
    let flow: FoodDecisionFlow
    let cuisine: Cuisine
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 32) {
            Text("How about…")
                .font(.title2)
                .foregroundStyle(.secondary)
                .padding(.top, 48)
            Spacer()
            VStack(spacing: 16) {
                Text(cuisine.emoji).font(.system(size: 96))
                Text(cuisine.name)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
            }
            .id(cuisine) // new identity per proposal so re-rolls animate
            .transition(.scale.combined(with: .opacity))
            Spacer()
            Text("Hand the phone over 📱")
                .font(.footnote)
                .foregroundStyle(.secondary)
            VStack(spacing: 12) {
                Button {
                    flow.agree(in: modelContext)
                } label: {
                    Label("Agree", systemImage: "checkmark")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)

                Button {
                    flow.reroll()
                } label: {
                    Label("Re-roll", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
    }
}

#Preview {
    DecideView(flow: FoodDecisionFlow(), cuisine: Cuisine(name: "Hotpot", emoji: "🍲"))
}
```

- [ ] **Step 3: Implement `OurApp/Modules/FoodDecision/Views/DecidedView.swift`**

```swift
import SwiftUI

struct DecidedView: View {
    let flow: FoodDecisionFlow
    let cuisine: Cuisine
    @State private var celebrate = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            VStack(spacing: 16) {
                Text(cuisine.emoji)
                    .font(.system(size: 96))
                    .scaleEffect(celebrate ? 1 : 0.3)
                Text("\(cuisine.name) it is! 🎉")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
            }
            Spacer()
            VStack(spacing: 12) {
                NavigationLink {
                    RestaurantListView(cuisine: cuisine)
                } label: {
                    Label("Find places near us", systemImage: "location.fill")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Start over") {
                    flow.startOver()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .sensoryFeedback(.success, trigger: celebrate)
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.5)) {
                celebrate = true
            }
        }
    }
}

#Preview {
    NavigationStack {
        DecidedView(flow: FoodDecisionFlow(), cuisine: Cuisine(name: "Hotpot", emoji: "🍲"))
    }
}
```

- [ ] **Step 4: Implement `OurApp/Modules/FoodDecision/FoodDecisionModule.swift`**

```swift
import SwiftUI

/// Module entry point (module contract: the one view the shell mounts).
struct FoodDecisionModuleView: View {
    @State private var flow = FoodDecisionFlow()

    var body: some View {
        NavigationStack {
            Group {
                switch flow.phase {
                case .propose:
                    ProposeView(flow: flow)
                case .deciding(let cuisine):
                    DecideView(flow: flow, cuisine: cuisine)
                case .decided(let cuisine):
                    DecidedView(flow: flow, cuisine: cuisine)
                }
            }
            .animation(.spring(duration: 0.35), value: flow.phase)
        }
    }
}

#Preview {
    FoodDecisionModuleView()
}
```

- [ ] **Step 5: Point `OurApp/App/AppShell.swift` at the module**

Replace the file body with:

```swift
import SwiftUI

/// The platform's module mount point. Today it mounts the only module directly;
/// when module #2 arrives this becomes a switcher (TabView or similar).
struct AppShell: View {
    var body: some View {
        FoodDecisionModuleView()
    }
}

#Preview {
    AppShell()
}
```

- [ ] **Step 6: Full suite + build**

Run: `xcodebuild test -project OurApp.xcodeproj -scheme OurApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: PASS.

- [ ] **Step 7: Run in the simulator and verify visually**

```bash
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
xcodebuild build -project OurApp.xcodeproj -scheme OurApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build -quiet
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/OurApp.app
# Simulate a Boston location (Northeastern) and pre-grant location so MapKit search works headlessly:
xcrun simctl location booted set 42.3398,-71.0892
xcrun simctl privacy booted grant location com.ourapp.OurApp || xcrun simctl privacy booted grant location-always com.ourapp.OurApp
xcrun simctl launch booted com.ourapp.OurApp
sleep 3
xcrun simctl io booted screenshot /private/tmp/claude-501/-Users-meixiaobin-Desktop-Our-App/814bea34-874e-4648-9367-b630a0384bc0/scratchpad/propose.png
```

Then **Read the screenshot** and confirm: 🍽️ header, "What should we eat?", a prominent "Surprise us" button, and the manual-entry field. (Button taps can't be scripted with simctl — the interactive loop is verified by the human; see Task 10.)

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Add food decision flow views and mount module in app shell"
```

---

### Task 10: Docs updates + final verification

Per the working agreement (§8): decisions made this session get appended to the right logs in the same session.

**Files:**
- Modify: `docs/DESIGN.md` (platform decision log §5, module index §6)
- Modify: `docs/modules/food-decision.md` (open questions)

**Interfaces:**
- Consumes: everything — this is the closing gate.
- Produces: updated docs, clean git history, a verified v1.

- [ ] **Step 1: Append to the platform decision log (§5 of `docs/DESIGN.md`)**

Add this row to the table after P2:

```markdown
| P3 | Hand-written `.xcodeproj` with Xcode 16 synchronized folder groups; shared scheme committed | No tool dependency, $0; folders auto-sync so sessions add files without ever editing the project file; headless `xcodebuild` works | XcodeGen (extra Homebrew dependency); scaffolding via the Xcode GUI (blocks CLI-driven sessions) |
```

- [ ] **Step 2: Update the Module Index row (§6 of `docs/DESIGN.md`)**

Change the food-decision row status from `🚧 In progress (v1)` to `🚧 v1 built — in real-use trial`.

- [ ] **Step 3: Record the open-question resolutions in `docs/modules/food-decision.md`**

Replace the two bullets under `## Module open questions` with:

```markdown
- ~~Bias the random pick by history from the start, or stay purely random until the history module lands?~~ **Resolved for v1 (2026-07-28): purely random.** History is recorded from day one, so nothing is lost; bias arrives with the history module.
- ~~`MKLocalSearch` region/radius — fixed, or adapt to how spread out results are?~~ **Resolved for v1 (2026-07-28): fixed ~5 km region, capped at 8 results.** Revisit if real use shows sparse/dense areas need adaptation.
```

- [ ] **Step 4: Final full verification**

Run: `xcodebuild test -project OurApp.xcodeproj -scheme OurApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: PASS — full suite green (Smoke, Persistence, CuisinePool, FoodDecisionFlow, RestaurantMapping, RestaurantSearch).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Record v1 decisions in platform and module docs"
```

- [ ] **Step 6: Hand off the human-verification checklist**

Tell the user the definition-of-done items only a human can confirm on the simulator/phone: random + typed proposal → agree/re-roll feel → decided celebration → real nearby restaurants with working Directions — then use it for real for a week before adding anything.
