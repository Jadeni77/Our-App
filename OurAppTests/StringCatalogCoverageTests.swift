import Foundation
import Testing
@testable import OurApp

/// Every literal `Text("…")` in the app must exist in the catalog, translated.
///
/// The existing completeness test checks that every key **in the catalog** has
/// all three languages — which cannot catch a string that never reached the
/// catalog at all. `Text("Time")` shipped that way: written into the 火花 sheet,
/// never added, and invisible until Xcode happened to extract it days later and
/// rewrite the file.
///
/// So this one starts from the *source* instead. It reads the repo through
/// `#filePath`, which is the only way a test bundle can see it.
struct StringCatalogCoverageTests {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // OurAppTests/
            .deletingLastPathComponent()   // repo root
    }

    @Test func everyLiteralTextIsInTheCatalogWithAllThreeLanguages() throws {
        let catalogURL = repoRoot.appending(path: "OurApp/Resources/Localizable.xcstrings")
        let catalog = try JSONSerialization.jsonObject(
            with: Data(contentsOf: catalogURL)) as? [String: Any] ?? [:]
        let strings = catalog["strings"] as? [String: Any] ?? [:]

        var missing: [String] = []
        var untranslated: [String] = []

        let sources = FileManager.default.enumerator(
            at: repoRoot.appending(path: "OurApp"), includingPropertiesForKeys: nil)
        while let url = sources?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for literal in Self.literalTextKeys(in: text) {
                guard let entry = strings[literal] as? [String: Any] else {
                    missing.append("\(url.lastPathComponent): \(literal)")
                    continue
                }
                let langs = Set((entry["localizations"] as? [String: Any] ?? [:]).keys)
                if !langs.isSuperset(of: ["en", "zh-Hans", "zh-Hant"]) {
                    untranslated.append("\(url.lastPathComponent): \(literal) has \(langs.sorted())")
                }
            }
        }

        #expect(missing.isEmpty, "Text literals absent from the catalog: \(missing)")
        #expect(untranslated.isEmpty, "Catalog entries missing a language: \(untranslated)")
    }

    /// `Text("…")` with a plain literal.
    ///
    /// Skipped deliberately, each for a reason rather than convenience:
    ///
    /// - **Comments.** The first run flagged three, all of them comments
    ///   warning about this very trap. A scanner that reads its own warnings
    ///   as violations is worse than none.
    /// - **`#Preview` blocks**, which are development scaffolding and never
    ///   shipped UI. Previews sit at the end of a file by convention here, so
    ///   scanning stops at the first one.
    /// - **`Text(verbatim:)`**, which exists precisely so a string *doesn't*
    ///   become a key.
    /// - **Interpolation**, whose catalog key is a format string (`"%lld days"`)
    ///   that would need reconstructing from Swift source.
    /// - **Strings with no letters** — emoji, dashes, ellipses — matching the
    ///   rule `LocalizationTests` already uses, so the two agree about what
    ///   counts as translatable.
    static func literalTextKeys(in source: String) -> [String] {
        let beforePreviews = source.components(separatedBy: "#Preview").first ?? source
        let source = beforePreviews
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                guard let comment = line.range(of: "//") else { return line }
                return line[line.startIndex..<comment.lowerBound]
            }
            .joined(separator: "\n")

        var keys: [String] = []
        var searchRange = source.startIndex..<source.endIndex
        while let open = source.range(of: "Text(\"", range: searchRange) {
            searchRange = open.upperBound..<source.endIndex
            guard let close = source.range(of: "\")", range: searchRange) else { break }
            let literal = String(source[open.upperBound..<close.lowerBound])
            if !literal.contains("\\("), !literal.contains("\""),
               literal.contains(where: \.isLetter) {
                keys.append(literal)
            }
            searchRange = close.upperBound..<source.endIndex
        }
        return keys
    }
}
