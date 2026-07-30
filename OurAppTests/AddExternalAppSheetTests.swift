import Foundation
import Testing
@testable import OurApp

struct AddExternalAppSheetTests {
    @Test func derivedSchemeLowercasesAndStripsToASCII() {
        #expect(AddExternalAppSheet.derivedScheme(from: "Identity V") == "identityv://")
        #expect(AddExternalAppSheet.derivedScheme(from: "Sky: Children of the Light 2") == "skychildrenofthelight2://")
    }

    @Test func derivedSchemeGivesUpWithoutASCII() {
        // A guessed scheme from a fully non-latin name would be junk —
        // better an empty field than a fake-looking one.
        #expect(AddExternalAppSheet.derivedScheme(from: "第五人格") == "")
    }

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

    @Test func schemeCandidatesCoverSquashInitialsAndFirstWord() {
        #expect(AddExternalAppSheet.schemeCandidates(from: "Honor of Kings")
                == ["honorofkings://", "hok://", "honor://"])
        #expect(AddExternalAppSheet.schemeCandidates(from: "Minecraft")
                == ["minecraft://"])
        // Squash and initials collide for short names — no duplicates.
        #expect(AddExternalAppSheet.schemeCandidates(from: "Wild Rift")
                == ["wildrift://", "wr://", "wild://"])
        #expect(AddExternalAppSheet.schemeCandidates(from: "第五人格") == [])
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
