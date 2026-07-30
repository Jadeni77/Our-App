import Foundation
import Testing
@testable import OurApp

struct ITunesSearchTests {
    @Test func searchURLQueriesSoftwareByName() throws {
        let url = try #require(ITunesSearch.searchURL(for: "Identity V"))
        let components = try #require(URLComponents(url: url,
                                                    resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https")
        #expect(components.host == "itunes.apple.com")
        #expect(components.path == "/search")
        let items = try #require(components.queryItems)
        #expect(items.contains(URLQueryItem(name: "term", value: "Identity V")))
        #expect(items.contains(URLQueryItem(name: "entity", value: "software")))
        #expect(items.contains(URLQueryItem(name: "limit", value: "1")))
    }

    @Test func firstResultParsesArtworkAndStoreLink() throws {
        let json = """
        {"resultCount":1,"results":[{"trackName":"Identity V",\
        "artworkUrl512":"https://example.com/icon.png",\
        "trackViewUrl":"https://apps.apple.com/app/id1191740709"}]}
        """
        let result = try #require(ITunesSearch.firstResult(from: Data(json.utf8)))
        #expect(result.trackName == "Identity V")
        #expect(result.artworkUrl512 == URL(string: "https://example.com/icon.png"))
        #expect(result.trackViewUrl == URL(string: "https://apps.apple.com/app/id1191740709"))
    }

    @Test func firstResultToleratesMissingFields() throws {
        let json = #"{"resultCount":1,"results":[{"trackName":"Mystery"}]}"#
        let result = try #require(ITunesSearch.firstResult(from: Data(json.utf8)))
        #expect(result.artworkUrl512 == nil)
        #expect(result.trackViewUrl == nil)
    }

    @Test func firstResultFailsSoftOnEmptyOrGarbage() {
        let empty = Data(#"{"resultCount":0,"results":[]}"#.utf8)
        #expect(ITunesSearch.firstResult(from: empty) == nil)
        #expect(ITunesSearch.firstResult(from: Data("not json".utf8)) == nil)
    }

    @Test func resultsParseManyMatchesWithSmallArtwork() throws {
        let json = """
        {"resultCount":2,"results":[\
        {"trackName":"Clash of Clans",\
        "artworkUrl100":"https://example.com/coc-small.png",\
        "artworkUrl512":"https://example.com/coc.png",\
        "trackViewUrl":"https://apps.apple.com/app/id529479190"},\
        {"trackName":"Clash Royale"}]}
        """
        let results = ITunesSearch.results(from: Data(json.utf8))
        #expect(results.count == 2)
        #expect(results[0].trackName == "Clash of Clans")
        #expect(results[0].artworkUrl100 == URL(string: "https://example.com/coc-small.png"))
        #expect(results[1].artworkUrl100 == nil)
        #expect(ITunesSearch.results(from: Data("junk".utf8)).isEmpty)
    }

    @Test func searchURLHonorsTheRequestedLimit() throws {
        let url = try #require(ITunesSearch.searchURL(for: "Clash", limit: 5))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(try #require(components.queryItems)
            .contains(URLQueryItem(name: "limit", value: "5")))
    }
}
