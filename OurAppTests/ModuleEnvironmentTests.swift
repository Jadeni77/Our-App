import Foundation
import Testing
@testable import OurApp

/// No module may read the shell's `CoupleIdentityStore` from the environment.
///
/// That store is declared on Home's `NavigationStack`. Modules mount from the
/// springboard and are **not** children of it, so reading it there traps the
/// moment the view appears — a crash with no compile error and no failing test,
/// which only shows up by opening the screen.
///
/// This has now happened twice: Daily Question shipped it, and after I wrote a
/// comment in `MoonshotHomeView` warning about it, co-op's match view did the
/// same thing and crashed on tapping a level. A comment is not a guard rail.
/// `LocalAuthor.id()` is the correct source — it needs no environment at all.
struct ModuleEnvironmentTests {
    private var modulesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "OurApp/Modules")
    }

    @Test func noModuleReadsTheShellsIdentityStoreFromTheEnvironment() throws {
        var offenders: [String] = []
        let files = FileManager.default.enumerator(at: modulesDirectory,
                                                   includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for (number, line) in source.split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated() {
                guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("///"),
                      !line.contains("//"),
                      line.contains("@Environment(CoupleIdentityStore.self)")
                else { continue }
                offenders.append("\(url.lastPathComponent):\(number + 1)")
            }
        }
        #expect(offenders.isEmpty,
                "Modules must use LocalAuthor.id(), not the shell's environment: \(offenders)")
    }
}
