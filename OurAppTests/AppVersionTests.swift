import Foundation
import Testing
@testable import OurApp

struct AppVersionTests {
    @Test func readsTheRunningBundlesVersionAndBuild() {
        // The test host is the app itself, so this exercises the real keys:
        // "version (build)", both numeric — never hardcoded anywhere (P13).
        let display = AppVersion.display()
        #expect(display.wholeMatch(of: /\d+(\.\d+)* \(\d+\)/) != nil,
                "unexpected version display: \(display)")
    }

    @Test func missingBundleKeysFailSoftToDashes() {
        // A bundle over a plain directory has no Info.plist keys.
        let empty = Bundle(path: FileManager.default.temporaryDirectory.path)
        let display = AppVersion.display(from: try! #require(empty))
        #expect(display == "— (—)")
    }
}
