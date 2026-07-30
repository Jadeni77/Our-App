import Foundation
import Testing
@testable import OurApp

struct AddExternalAppSheetTests {
    @Test func duplicateNamesAreCaughtCaseInsensitivelyAndTrimmed() {
        let identity = GamesLayout.ExternalApp(
            id: UUID(), name: "Identity V", emoji: "🎮",
            artworkURL: nil, launchURL: nil, storeURL: nil)
        #expect(AddExternalAppSheet.isDuplicateName("identity v ", among: [identity],
                                                    excluding: nil))
        #expect(!AddExternalAppSheet.isDuplicateName("Identity V 2", among: [identity],
                                                     excluding: nil))
        // Editing an entry may keep its own name.
        #expect(!AddExternalAppSheet.isDuplicateName("Identity V", among: [identity],
                                                     excluding: identity.id))
    }

    @Test func launchURLNormalizationEncodesSpacesAndAddsScheme() throws {
        // A bare word becomes a scheme; a shortcuts link with a spaced name
        // gets percent-encoded instead of silently failing.
        #expect(AddExternalAppSheet.normalizedLaunchURL(from: "identityv")
                == URL(string: "identityv://"))
        #expect(AddExternalAppSheet.normalizedLaunchURL(from: "  ") == nil)
        let spaced = try #require(AddExternalAppSheet.normalizedLaunchURL(
            from: "shortcuts://run-shortcut?name=Identity V"))
        #expect(spaced.absoluteString == "shortcuts://run-shortcut?name=Identity%20V")
    }
}
