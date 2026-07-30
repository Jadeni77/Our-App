import Foundation

/// Everything the springboard knows about launch schemes (S7). iOS has no
/// name→scheme lookup, so this is two things: the couple's hand-verified
/// catalog (each entry earned on a real phone), and a generator for the
/// likely guesses the probe and the self-healing launch walk through.
enum SchemeCatalog {
    /// Verified on-device — matched by containment so store-style titles
    /// ("League of Legends: Wild Rift") still hit their everyday names.
    /// `displayName` is what the phone's home screen shows (no API exposes
    /// it, so it's curated alongside the scheme).
    private struct Entry {
        let fragment: String
        let scheme: String
        let displayName: String
    }

    private static let verifiedEntries: [Entry] = [
        .init(fragment: "wild rift", scheme: "wildrift://",
              displayName: "Wild Rift"),                       // verified 2026-07-30
        .init(fragment: "clash of clans", scheme: "clashofclans://",
              displayName: "Clash of Clans"),                  // verified 2026-07-30
    ]

    static func verified(for title: String) -> String? {
        entry(for: title)?.scheme
    }

    static func displayName(for title: String) -> String? {
        entry(for: title)?.displayName
    }

    private static func entry(for title: String) -> Entry? {
        let haystack = title.lowercased()
        return verifiedEntries.first { haystack.contains($0.fragment) }
    }

    /// The likely schemes for a title, most promising first: the subtitle's
    /// squash (store titles wrap the real name after a colon/dash), the full
    /// squash, initials, subtitle initials, first word — deduped; empty for
    /// fully non-latin titles.
    static func candidates(from title: String) -> [String] {
        let fullWords = asciiWords(of: title)
        guard !fullWords.isEmpty else { return [] }

        let separators = CharacterSet(charactersIn: ":-–")
        let subtitle = title.components(separatedBy: separators).last
            .map(asciiWords(of:)) ?? []
        let subtitleIsDistinct = !subtitle.isEmpty && subtitle != fullWords

        var candidates: [String] = []
        if subtitleIsDistinct {
            candidates.append(subtitle.joined() + "://")
        }
        candidates.append(fullWords.joined() + "://")
        if fullWords.count >= 2 {
            candidates.append(fullWords.map { String($0.prefix(1)) }.joined() + "://")
        }
        if subtitleIsDistinct, subtitle.count >= 2 {
            candidates.append(subtitle.map { String($0.prefix(1)) }.joined() + "://")
        }
        if fullWords.count >= 2 {
            candidates.append(fullWords[0] + "://")
        }
        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    /// Schemes this build declared in `LSApplicationQueriesSchemes` — the
    /// only ones `canOpenURL` can answer for.
    static var declaredSchemes: Set<String> {
        let declared = Bundle.main.object(
            forInfoDictionaryKey: "LSApplicationQueriesSchemes") as? [String]
        return Set(declared ?? [])
    }

    /// Which candidates are worth actually opening, in order:
    /// 1. declared **and** installed — iOS confirmed these exist, so the
    ///    first one launches (one system prompt, no wasted bounces);
    /// 2. undeclared — `canOpenURL` can't answer, so they stay blind attempts;
    /// 3. declared but absent — dropped: iOS already proved the app isn't
    ///    here, and firing `open()` at it only asks the owners for nothing.
    static func plan(candidates: [String],
                     declared: Set<String>,
                     canOpen: (String) -> Bool) -> [String] {
        var seen = Set<String>()
        var installed: [String] = []
        var unknown: [String] = []
        for candidate in candidates where seen.insert(candidate).inserted {
            let scheme = candidate.components(separatedBy: "://").first ?? candidate
            if declared.contains(scheme) {
                if canOpen(candidate) { installed.append(candidate) }
            } else {
                unknown.append(candidate)
            }
        }
        return installed + unknown
    }

    private static func asciiWords(of title: String) -> [String] {
        title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.allSatisfy(\.isASCII) }
    }
}
