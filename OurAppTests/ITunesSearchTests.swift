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

    @Test func searchURLCarriesTheStorefrontCountry() throws {
        let url = try #require(ITunesSearch.searchURL(for: "第五人格", country: "CN"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(try #require(components.queryItems)
            .contains(URLQueryItem(name: "country", value: "CN")))

        // No region → no parameter; the API then applies its own default.
        let bare = try #require(ITunesSearch.searchURL(for: "Clash", country: nil))
        let bareComponents = try #require(URLComponents(url: bare,
                                                        resolvingAgainstBaseURL: false))
        let bareItems = try #require(bareComponents.queryItems)
        #expect(!bareItems.contains { $0.name == "country" })
    }

    @Test func blankTrackNamesNeverSurviveParsing() {
        // A titleless result can't be shown in the picker and must never
        // become a tile's name — sanity-checked at the parse boundary.
        let json = """
        {"resultCount":3,"results":[\
        {"trackName":"  "},\
        {"trackName":""},\
        {"trackName":"Real Game"}]}
        """
        let results = ITunesSearch.results(from: Data(json.utf8))
        #expect(results.map(\.trackName) == ["Real Game"])
    }

    @Test func plausibleMatchAcceptsContainmentEitherWay() {
        // The store title often wraps the typed name ("Wild Rift" →
        // "League of Legends: Wild Rift") — and vice versa.
        #expect(ITunesSearch.plausibleMatch(typed: "Wild Rift",
                                            trackName: "League of Legends: Wild Rift"))
        #expect(ITunesSearch.plausibleMatch(typed: "Clash of Clans ",
                                            trackName: "clash of clans"))
        #expect(ITunesSearch.plausibleMatch(typed: "League of Legends: Wild Rift",
                                            trackName: "Wild Rift"))
    }

    @Test func plausibleMatchRejectsUnrelatedTitles() {
        #expect(!ITunesSearch.plausibleMatch(typed: "第五人格",
                                             trackName: "Candy Crush Saga"))
        #expect(!ITunesSearch.plausibleMatch(typed: "", trackName: "Anything"))
    }
}
