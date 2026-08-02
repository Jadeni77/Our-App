import Foundation

/// One scripted demonstration (owner amendment #3): a tiny synthetic
/// stage, the fling, and when (if ever) to tap. The dashboard and the
/// teaching cards play these through a REAL GameScene on a loop — live
/// physics, not videos (principle 9). `abilityDelay` nil = no tap: the
/// gloom introductions (owner amendment 2026-08-02) script the most
/// natural attack FAILING, and a fail demo never fires a power.
struct AbilityDemo {
    let level: MoonshotLevel
    let pull: (dx: Double, dy: Double)
    let abilityDelay: TimeInterval?
}

enum AbilityDemos {
    static func demo(for character: CharacterID) -> AbilityDemo {
        switch character {
        case .mochi:
            // Slam over a stone roof: the drop is the whole story.
            AbilityDemo(level: stage(character,
                                     pieces: [
                                         piece(.column, .meteorstone, 600, 45),
                                         piece(.column, .meteorstone, 700, 45),
                                         piece(.plank, .meteorstone, 650, 102),
                                     ],
                                     glooms: [.init(x: 650, y: 16)]),
                        pull: (dx: -53, dy: -53), abilityDelay: 1.1)
        case .zip:
            // A flat line into a crystal wall: dash punches through.
            AbilityDemo(level: stage(character,
                                     pieces: [
                                         piece(.column, .crystal, 640, 45),
                                         piece(.column, .crystal, 640, 134),
                                     ],
                                     glooms: [.init(x: 700, y: 16)]),
                        pull: (dx: -70, dy: -14), abilityDelay: 0.45)
        case .twinkle:
            // Split at apex over two perches: one star becomes two.
            AbilityDemo(level: stage(character,
                                     pieces: [
                                         piece(.column, .moonwood, 600, 45),
                                         piece(.column, .moonwood, 720, 45),
                                     ],
                                     glooms: [.init(x: 600, y: 106), .init(x: 720, y: 106)]),
                        pull: (dx: -56, dy: -50), abilityDelay: 0.55)
        case .nox:
            // A sealed frame-roofed vault: only the well opens it.
            AbilityDemo(level: stage(character,
                                     pieces: [
                                         piece(.column, .meteorstone, 620, 45),
                                         piece(.column, .meteorstone, 720, 45),
                                         piece(.plank, .frame, 670, 102),
                                     ],
                                     glooms: [.init(x: 670, y: 16)]),
                        pull: (dx: -50, dy: -56), abilityDelay: 0.85)
        case .misty:
            // A wood wall she has no business passing — and does.
            AbilityDemo(level: stage(character,
                                     pieces: [
                                         piece(.column, .moonwood, 640, 45),
                                         piece(.column, .moonwood, 640, 134),
                                     ],
                                     glooms: [.init(x: 700, y: 16)]),
                        pull: (dx: -64, dy: -30), abilityDelay: 0.5)
        case .pogo:
            // Primed before the ground, he springs OVER the wall onto the
            // perch — the ricochet keeps every bit of his speed (M35).
            AbilityDemo(level: stage(character,
                                     pieces: [
                                         piece(.column, .moonwood, 660, 45),
                                         piece(.column, .moonwood, 760, 45),
                                     ],
                                     glooms: [.init(x: 760, y: 106)]),
                        pull: (dx: -50, dy: -40), abilityDelay: 0.8)
        }
    }

    private static func piece(_ shape: PieceShape, _ material: Material,
                              _ x: Double, _ y: Double) -> MoonshotLevel.Piece {
        .init(shape: shape, material: material, x: x, y: y, rotation: 0)
    }

    fileprivate static func stage(_ character: CharacterID,
                                  pieces: [MoonshotLevel.Piece] = [],
                                  glooms: [MoonshotLevel.GloomPlacement]) -> MoonshotLevel {
        MoonshotLevel(schemaVersion: 1,
                      id: UUID(),
                      kind: .campaign, authorID: nil,
                      createdAt: .now, updatedAt: .now, deletedAt: nil,
                      title: nil,
                      par: 1,
                      queue: [character, character, character],
                      buildZone: .init(x: 500, y: 0, width: 320, height: 340),
                      pieces: pieces,
                      glooms: glooms)
    }
}

/// A gloom kind's introduction (owner amendment 2026-08-02): mochi throws
/// the most NATURAL attack and it fails, on loop, mid-level, until the
/// player dismisses it — the lesson is what doesn't work; the card's
/// caption names the counter. Every pull below is anchored ballistics:
/// v = pull×9, the (-53,-53) arc lands a direct hit at x≈597 and a
/// ground roll from x≈627.
enum GloomDemos {
    static func demo(for kind: GloomKind) -> AbilityDemo {
        switch kind {
        case .shield:
            // A clean direct hit — the shell eats it whole, the gloom lives.
            AbilityDemo(level: AbilityDemos.stage(.mochi, glooms: [.init(x: 600, y: 16, kind: .shield)]),
                        pull: (dx: -53, dy: -53), abilityDelay: nil)
        case .hopper:
            // A landing right beside it — the bait IS the miss: it leaps.
            AbilityDemo(level: AbilityDemos.stage(.mochi, glooms: [.init(x: 700, y: 16, kind: .hopper)]),
                        pull: (dx: -55, dy: -55), abilityDelay: nil)
        case .mist:
            // A powerless roll straight through the vapor — nothing at all.
            AbilityDemo(level: AbilityDemos.stage(.mochi, glooms: [.init(x: 680, y: 16, kind: .mist)]),
                        pull: (dx: -53, dy: -53), abilityDelay: nil)
        case .great:
            // A full arc into the mountain — one chip of five, and anger.
            AbilityDemo(level: AbilityDemos.stage(.mochi, glooms: [.init(x: 650, y: 48, kind: .great)]),
                        pull: (dx: -55, dy: -55), abilityDelay: nil)
        case .helmet:
            // The sky-hit — the exact L43-verified shrug geometry: clink.
            AbilityDemo(level: AbilityDemos.stage(.mochi, glooms: [.init(x: 600, y: 16, kind: .helmet)]),
                        pull: (dx: -53, dy: -53), abilityDelay: nil)
        }
    }
}
