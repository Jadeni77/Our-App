import Foundation

/// The keyless iTunes Search API (S7): one request enriches a manually added
/// game with official artwork and its App Store page. Every failure is soft —
/// callers get nil and the tile keeps its emoji fallback.
enum ITunesSearch {
    struct Result: Decodable, Equatable, Hashable {
        let trackName: String
        /// Small icon for pickers; the tile itself caches the 512 version.
        let artworkUrl100: URL?
        let artworkUrl512: URL?
        let trackViewUrl: URL?
    }

    private struct Response: Decodable {
        let results: [Result]
    }

    static func searchURL(for name: String, limit: Int = 1,
                          country: String? = Locale.current.region?.identifier) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "term", value: name),
            URLQueryItem(name: "entity", value: "software"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        // Without a storefront the API defaults to the US: games the owners
        // know by their local titles can miss entirely (post-#14 follow-up).
        // Only a plausible ISO code goes on the wire — Locale can yield
        // regions like "419" (Latin America), which the API rejects with an
        // error payload that would silently zero the whole search.
        if let country, country.count == 2,
           country.allSatisfy({ $0.isASCII && $0.isLetter }) {
            components.queryItems?.append(URLQueryItem(name: "country", value: country))
        }
        return components.url
    }

    static func results(from data: Data) -> [Result] {
        let decoded = (try? JSONDecoder().decode(Response.self, from: data))?.results ?? []
        // A result with a blank title can't be shown in the picker or become
        // a tile name — drop it before anything downstream dresses with it.
        return decoded.filter {
            !$0.trackName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    static func firstResult(from data: Data) -> Result? {
        results(from: data).first
    }

    /// Live-picker search: a handful of matches by name. Fails soft to [].
    static func search(name: String, limit: Int = 5,
                       country: String? = Locale.current.region?.identifier)
        async -> [Result] {
        guard let url = searchURL(for: name, limit: limit, country: country)
        else { return [] }
        let request = URLRequest(url: url, timeoutInterval: 4)
        guard let (data, _) = try? await URLSession.shared.data(for: request)
        else { return [] }
        return results(from: data)
    }

    /// Enrichment lookup: deliberately storefront-agnostic. A regional
    /// storefront localizes `trackName` ("Identity V" → "第五人格"), which
    /// fails `plausibleMatch` against the typed name and strips tiles of
    /// artwork/store links — the picker shows local titles; matching wants
    /// the default ones (review ruling, this branch).
    static func lookup(name: String) async -> Result? {
        await search(name: name, limit: 1, country: nil).first
    }

    /// Search is fuzzy; dressing a tile with a stranger's artwork isn't ok.
    /// A match is plausible when one title contains the other (trimmed,
    /// case-insensitive) — "Wild Rift" ⊂ "League of Legends: Wild Rift".
    static func plausibleMatch(typed: String, trackName: String) -> Bool {
        let a = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let b = trackName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a == b || b.contains(a) || a.contains(b)
    }
}
