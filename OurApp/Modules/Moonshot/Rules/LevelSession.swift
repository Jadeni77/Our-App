import Foundation
import Observation

/// The fling state machine — pure Rules, no SpriteKit. The Engine drives it
/// (aim, fling, ability tap, flight end, settle) and reads phase back; win is
/// only ever evaluated at settle, matching the spec's "all Glooms popped after
/// physics settles". @Observable so the HUD re-renders as phases change —
/// Observation is Foundation-tier, so the no-UI-imports rule holds.
@Observable
final class LevelSession {
    enum Phase: Equatable {
        case ready, aiming, inFlight, settling
        case won(stars: Int)
        case failed
    }

    let level: MoonshotLevel
    private(set) var phase: Phase = .ready
    private(set) var flingsUsed = 0
    private(set) var gloomsRemaining: Int
    private(set) var abilityUsedThisFlight = false
    /// Cumulative across the whole level — feeds the NO ABILITY feat (M23).
    private(set) var usedAnyAbility = false

    /// Head of the queue; nil once exhausted. The head stays current through
    /// the whole flight and is consumed on `settled()`.
    var currentCharacter: CharacterID? { remainingQueue.first }
    /// What's left to fling, current character first — the HUD renders this.
    var upcomingCharacters: [CharacterID] { remainingQueue }
    private var remainingQueue: [CharacterID]

    init(level: MoonshotLevel) {
        self.level = level
        remainingQueue = level.queue
        gloomsRemaining = level.glooms.count
    }

    /// One free-choice swap per level (M-design: Nox is a choice, never a
    /// requirement). The session enforces phase + once-only; whether the
    /// character is unlocked is the caller's job — Rules doesn't know pools.
    private(set) var usedCharacterSwap = false

    func swapCurrentCharacter(to character: CharacterID) {
        guard phase == .ready, !usedCharacterSwap,
              !remainingQueue.isEmpty, remainingQueue[0] != character else { return }
        usedCharacterSwap = true
        remainingQueue[0] = character
    }

    func beginAim() {
        guard phase == .ready, currentCharacter != nil else { return }
        phase = .aiming
    }

    func cancelAim() {
        guard phase == .aiming else { return }
        phase = .ready
    }

    func fling() {
        guard phase == .aiming else { return }
        flingsUsed += 1
        phase = .inFlight
    }

    /// One tap per flight: returns the flying character the first time,
    /// nil ever after (and always nil outside flight).
    func tapAbility() -> CharacterID? {
        guard phase == .inFlight, !abilityUsedThisFlight, let character = currentCharacter else { return nil }
        abilityUsedThisFlight = true
        usedAnyAbility = true
        return character
    }

    func flightEnded() {
        guard phase == .inFlight else { return }
        phase = .settling
    }

    func gloomPopped() {
        gloomsRemaining = max(0, gloomsRemaining - 1)
    }

    func settled() {
        guard phase == .settling else { return }
        if !remainingQueue.isEmpty { remainingQueue.removeFirst() }
        abilityUsedThisFlight = false
        if gloomsRemaining == 0 {
            phase = .won(stars: MoonshotScoring.stars(cleared: true, flingsUsed: flingsUsed, par: level.par))
        } else if remainingQueue.isEmpty {
            phase = .failed
        } else {
            phase = .ready
        }
    }
}
