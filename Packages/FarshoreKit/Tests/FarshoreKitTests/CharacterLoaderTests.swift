import Foundation
import Testing
@testable import FarshoreKit

/// The drop-in contract, from the other side: this is what proves the
/// fallback actually falls back. `.module` currently has no `character.scn`
/// or `character.dae` — the owner's Mixamo export doesn't exist yet — so
/// today `CharacterLoader.make(in:)` must resolve to `MannequinCharacter`.
/// The moment the owner's files land in `Resources/`, this same assertion
/// starts failing, which is the correct and expected signal that the
/// drop-in worked — see the task-3A report for what to do at that point
/// (update this test to expect `RiggedCharacter` instead).
struct CharacterLoaderTests {
    @Test func fallsBackToTheMannequinWhenNoRiggedExportIsPresent() {
        let character = CharacterLoader.make(in: .module)
        #expect(character is MannequinCharacter)
    }
}
