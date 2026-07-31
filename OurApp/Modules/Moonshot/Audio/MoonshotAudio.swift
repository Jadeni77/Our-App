import AVFoundation
import SpriteKit

/// Owns the audio session and the ambient loop — never SFX (those play
/// scene-local through `SoundBank` for latency). The `.ambient` category is
/// the spec's mute-switch requirement: silent switch silences everything.
@MainActor
final class MoonshotAudio {
    static let shared = MoonshotAudio()

    private var ambiencePlayer: AVAudioPlayer?
    private let ambienceVolume: Float = 0.55   // the device pass's knob

    var musicEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "moonshot.music") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "moonshot.music")
            // Stop-only: the game view is the sole starter — toggling ON at
            // the home screen must not leak the pad past the module
            // (review finding: it played app-wide forever).
            if !newValue { stopAmbience() }
        }
    }

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
    }

    func startAmbience() {
        guard musicEnabled, ambiencePlayer?.isPlaying != true else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let url = Bundle.main.url(forResource: "ambience", withExtension: "caf") else { return }
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = -1   // the 16 s pad is loop-matched by construction
        player?.volume = ambienceVolume
        player?.play()
        ambiencePlayer = player
    }

    func stopAmbience() {
        ambiencePlayer?.stop()
        ambiencePlayer = nil
    }
}

/// Scene-local SFX: cached `SKAction`s keyed by what happened. Cached once —
/// `playSoundFileNamed` preloads on first construction, and a cache miss at
/// impact time would hitch the physics frame.
@MainActor
enum SoundBank {
    private static var cache: [String: SKAction] = [:]

    private static func action(named name: String) -> SKAction {
        if let cached = cache[name] { return cached }
        let action = SKAction.playSoundFileNamed("\(name).caf", waitForCompletion: false)
        cache[name] = action
        return action
    }

    static let stretch = SKAction.playSoundFileNamed("stretch.caf", waitForCompletion: false)

    /// Build every action up front (scene load), because
    /// `playSoundFileNamed` reads its file at construction — the first
    /// mid-flight impact must never pay that cost.
    static func prewarm() {
        _ = stretch
        for material in Material.allCases { _ = action(for: .impact(material)) }
        _ = action(for: .flung)
        _ = action(for: .gloomPopped)
        _ = action(for: .levelWon(stars: 3))
        for character in CharacterID.allCases { _ = abilityAction(for: character) }
    }

    static func action(for event: GameEvent) -> SKAction? {
        switch event {
        case .flung:
            action(named: "release")
        case .impact(let material), .pieceDestroyed(let material):
            switch material {
            case .crystal: action(named: "impact-crystal")
            case .moonwood: action(named: "impact-moonwood")
            case .cloudfoam: action(named: "boing")
            case .meteorstone, .frame: action(named: "impact-stone")
            }
        case .gloomPopped:
            action(named: "gloom-pop")
        case .levelWon:
            action(named: "chime")
        case .levelFailed:
            nil
        }
    }

    static func abilityAction(for character: CharacterID) -> SKAction {
        switch character {
        case .mochi: action(named: "slam")
        case .zip: action(named: "dash")
        case .twinkle: action(named: "split")
        case .nox: action(named: "well")
        case .misty: action(named: "phase")
        }
    }
}
