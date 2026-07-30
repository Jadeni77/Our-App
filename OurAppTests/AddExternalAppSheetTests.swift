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
}
