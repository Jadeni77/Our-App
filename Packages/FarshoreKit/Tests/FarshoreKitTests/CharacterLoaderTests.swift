import Foundation
import SceneKit
import Testing
@testable import FarshoreKit

/// **What these tests pin — and, just as importantly, what they do not.**
///
/// An earlier version of this file claimed to be the signal that the owner's
/// Mixamo drop-in had worked. It was not, and could not have been: it asserted
/// only that the loader falls back when *nothing* is present, so it stayed
/// green in precisely the case that mattered — a `character.dae` sitting in
/// `Resources/` that iOS silently cannot parse, because iOS has no Collada
/// importer. A test whose stated job is to detect a broken drop-in, and which
/// passes while the drop-in is broken, is worse than no test: it gets read as
/// reassurance.
///
/// So these pin three things that are actually true here and now: the fallback
/// when nothing is supplied, the filenames the drop-in instructions name, and
/// the behaviour when a file **is** present but unusable. Whether the owner's
/// real export loads is a property of a file that does not exist yet, and no
/// test in this package can know it in advance — `CharacterLoader`'s log line
/// is that signal, not this file.
///
/// **The multi-file shape lives in `CharacterClipFileTests`.** Mixamo hands out
/// one animation per download, so the rig may be accompanied by optional
/// `character-idle.scn` and `character-walk.scn`. Those tests build real `.scn`
/// files at run time and drive the loader over them, which is as close to the
/// owner's actual hand-over as this package can get before it happens.
struct CharacterLoaderTests {
    @Test func fallsBackToTheMannequinWhenNoRiggedExportIsPresent() {
        // Guard the premise. Without this, the day someone adds a real export
        // this test would keep "passing" for a while and then start failing
        // for a reason nobody could read off the assertion.
        #expect(RiggedCharacter.resourceURL(for: CharacterLoader.riggedSceneFilename, in: .module) == nil)
        #expect(RiggedCharacter.resourceURL(for: CharacterLoader.riggedDaeFilename, in: .module) == nil)

        #expect(CharacterLoader.make(in: .module) is MannequinCharacter)
    }

    /// The filenames are the drop-in contract's entire user interface: the
    /// owner is told, in `CharacterLoader`'s comment and in `ASSETS.md`, to
    /// name their converted export `character.scn`. Rename the constant and
    /// those instructions become wrong silently — the same class of failure
    /// this whole fix round is about.
    @Test func theDropInFilenamesAreTheOnesDocumented() {
        #expect(CharacterLoader.riggedSceneFilename == "character.scn")
        #expect(CharacterLoader.riggedDaeFilename == "character.dae")
    }

    /// **The case that was silently broken.** A file is sitting in the
    /// resources folder under the expected name and SceneKit cannot make a
    /// scene out of it — which is exactly what a raw Mixamo `.dae` does on
    /// iOS. The app must still come up wearing the mannequin (principle 7,
    /// fail soft) rather than crash or render nothing.
    ///
    /// Uses a throwaway bundle built in the temp directory, so it exercises
    /// the real `make(in:)` path against a real unusable file without
    /// shipping a broken asset inside `Resources/`.
    @Test func fallsBackToTheMannequinWhenAnExportIsPresentButUnusable() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(UUID().uuidString).bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data("this is not a SceneKit scene".utf8)
            .write(to: dir.appendingPathComponent(CharacterLoader.riggedSceneFilename))

        let bundle = try #require(Bundle(url: dir))
        // Premise: the loader really is finding the file, so what follows is
        // the present-but-unusable path and not just the missing-file path
        // wearing a disguise.
        #expect(RiggedCharacter.resourceURL(for: CharacterLoader.riggedSceneFilename, in: bundle) != nil)
        #expect(RiggedCharacter(sceneNamed: CharacterLoader.riggedSceneFilename, in: bundle) == nil)

        #expect(CharacterLoader.make(in: bundle) is MannequinCharacter)
    }
}
