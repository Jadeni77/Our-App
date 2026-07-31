import SpriteKit
import Testing
@testable import OurApp

@MainActor struct MoonshotAudioTests {
    /// `playSoundFileNamed` raises at construction when a file is missing —
    /// this turns a renamed/dropped .caf into a test failure, not a crash
    /// on someone's first fling.
    @Test func everySoundFileResolves() {
        SoundBank.prewarm()
        for material in Material.allCases {
            #expect(SoundBank.action(for: .impact(material)) != nil)
            #expect(SoundBank.action(for: .pieceDestroyed(material)) != nil)
        }
        #expect(SoundBank.action(for: .flung) != nil)
        #expect(SoundBank.action(for: .gloomPopped) != nil)
        #expect(SoundBank.action(for: .levelWon(stars: 1)) != nil)
        #expect(SoundBank.action(for: .levelFailed) == nil)   // fail is silent by design
    }

    /// Regression: a HUD tap can reach the scene before SpriteKit presents
    /// it (no slingshot yet) — the swap must take in the session without
    /// trapping in `seatNextSprite` (crashed in the wild before the guard).
    @Test func characterSwapBeforePresentationDoesNotTrap() {
        let level = CampaignCatalog.bundled.levels[0]
        let session = LevelSession(level: level)
        let scene = GameScene(level: level, session: session)
        scene.swapSeatedCharacter(to: .nox)   // scene never presented
        #expect(session.currentCharacter == .nox)
    }
}
