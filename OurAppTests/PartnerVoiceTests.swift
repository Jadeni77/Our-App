import Foundation
import Testing
@testable import OurApp

/// The app used to say "her" about everybody's partner.
struct PartnerVoiceTests {
    private func defaults(_ name: String = UUID().uuidString) throws -> UserDefaults {
        try #require(UserDefaults(suiteName: name))
    }

    /// they/them when we haven't been told — never wrong about someone whose
    /// preference the app does not have.
    @Test func theDefaultAssumesNothing() throws {
        let store = try defaults()
        #expect(PartnerVoice.pronoun(defaults: store) == .they)
        #expect(PartnerVoice.label(defaults: store) == "them")
    }

    @Test func eachChoiceIsRemembered() throws {
        for choice in PartnerVoice.Pronoun.allCases {
            let store = try defaults()
            PartnerVoice.setPronoun(choice, defaults: store)
            #expect(PartnerVoice.pronoun(defaults: store) == choice)
        }
    }

    /// A name beats every pronoun. "Waiting for Yuki" is both warmer and
    /// incapable of being wrong.
    @Test func aNameIsUsedWheneverThereIsOne() throws {
        let store = try defaults()
        PartnerVoice.setPronoun(.she, defaults: store)
        store.set("Yuki", forKey: CoupleIdentityStore.Keys.nameTwo)
        #expect(PartnerVoice.label(defaults: store) == "Yuki")
    }

    /// Whitespace is not a name — it would render "Waiting for " with nothing
    /// after it, which reads as a bug rather than as a partner.
    @Test func aBlankNameFallsBackToThePronoun() throws {
        let store = try defaults()
        PartnerVoice.setPronoun(.he, defaults: store)
        store.set("   ", forKey: CoupleIdentityStore.Keys.nameTwo)
        #expect(PartnerVoice.label(defaults: store) == "him")
    }

    /// The name has to come from the same key the settings screen writes.
    /// Two spellings of one key is a setting that silently does nothing.
    @MainActor
    @Test func itReadsTheKeyTheSettingsScreenWrites() throws {
        let store = try defaults()
        let identity = CoupleIdentityStore(defaults: store)
        identity.nameTwo = "Wren"
        #expect(PartnerVoice.label(defaults: store) == "Wren")
    }
}
