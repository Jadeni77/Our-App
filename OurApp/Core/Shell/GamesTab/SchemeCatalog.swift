import Foundation

/// Everything the springboard knows about launch schemes (S7). iOS has no
/// name→scheme lookup, so this is two things: the couple's hand-verified
/// catalog (each entry earned on a real phone), and a generator for the
/// likely guesses the probe and the self-healing launch walk through.
enum SchemeCatalog {
    /// Verified on-device — matched by containment so store-style titles
    /// ("League of Legends: Wild Rift") still hit their everyday names.
    private static let verifiedByFragment: [(fragment: String, scheme: String)] = [
        ("wild rift", "wildrift://"),           // verified 2026-07-30
        ("clash of clans", "clashofclans://"),  // verified 2026-07-30
    ]

    static func verified(for title: String) -> String? {
        let haystack = title.lowercased()
        return verifiedByFragment.first { haystack.contains($0.fragment) }?.scheme
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

    private static func asciiWords(of title: String) -> [String] {
        title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.allSatisfy(\.isASCII) }
    }
}
