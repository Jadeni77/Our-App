import Foundation
import Testing
@testable import OurApp

struct AppVersionTests {
    @Test func readsTheRunningBundlesVersionAndBuild() {
        // The test host is the app itself, so this exercises the real keys:
        // "version (build)", both numeric — never hardcoded anywhere (P13).
        // (Extended delimiters: bare-slash regex needs a compiler flag the
        // project doesn't set; #/…/# doesn't.)
        let display = AppVersion.display()
        #expect(display.wholeMatch(of: #/\d+(?:\.\d+)* \(\d+\)/#) != nil,
                "unexpected version display: \(display)")
    }

    @Test func missingBundleKeysFailSoftToDashes() throws {
        // A bundle over a plain empty directory has no Info.plist keys — a
        // unique one, so parallel suites sharing the temp root can't collide
        // (Foundation also caches Bundle by path for the process lifetime).
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("empty-bundle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        let empty = try #require(Bundle(path: directory.path))
        #expect(AppVersion.display(from: empty) == "— (—)")
    }
}
