import Foundation

/// The keyless iTunes Search API (S7): one request enriches a manually added
/// game with official artwork and its App Store page. Every failure is soft —
/// callers get nil and the tile keeps its emoji fallback.
enum ITunesSearch {
    struct Result: Decodable, Equatable {
        let trackName: String
        let artworkUrl512: URL?
        let trackViewUrl: URL?
    }

    private struct Response: Decodable {
        let results: [Result]
    }

    static func searchURL(for name: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "term", value: name),
            URLQueryItem(name: "entity", value: "software"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        return components.url
    }

    static func firstResult(from data: Data) -> Result? {
        (try? JSONDecoder().decode(Response.self, from: data))?.results.first
    }

    static func lookup(name: String) async -> Result? {
        guard let url = searchURL(for: name) else { return nil }
        // Short timeout: the add sheet awaits this before the tile appears.
        let request = URLRequest(url: url, timeoutInterval: 4)
        guard let (data, _) = try? await URLSession.shared.data(for: request)
        else { return nil }
        return firstResult(from: data)
    }
}
