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
}
