import Testing
@testable import OurApp

struct MoonshotCharactersTests {
    @Test func everyCharacterHasABody() {
        for character in CharacterID.allCases {
            #expect(character.radius > 0)
            #expect(character.density > 0)
        }
    }

    @Test func displayNameKeysAreTheCatalogKeys() {
        #expect(CharacterID.allCases.map(\.displayNameKey) == ["Mochi", "Zip", "Twinkle", "Nox"])
    }

    @Test func mochiIsTheHeavyOneZipTheNimbleOne() {
        // The teaching arc leans on this: the starter hits hard, the comet
        // flies fast — if these flip, levels 4–6 stop making sense.
        #expect(CharacterID.mochi.density > CharacterID.zip.density)
        #expect(CharacterID.zip.radius < CharacterID.mochi.radius)
    }
}
