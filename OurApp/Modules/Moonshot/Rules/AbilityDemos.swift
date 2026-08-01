import Foundation

/// One character's scripted demonstration (owner amendment #3): a tiny
/// synthetic stage, the fling that shows the power off, and when to tap.
/// The dashboard plays these through a REAL GameScene on a loop — live
/// physics, not videos (principle 9).
struct AbilityDemo {
    let level: MoonshotLevel
    let pull: (dx: Double, dy: Double)
    let abilityDelay: TimeInterval
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
                                     glooms: [(650, 16)]),
                        pull: (dx: -53, dy: -53), abilityDelay: 1.1)
        case .zip:
            // A flat line into a crystal wall: dash punches through.
            AbilityDemo(level: stage(character,
                                     pieces: [
                                         piece(.column, .crystal, 640, 45),
                                         piece(.column, .crystal, 640, 134),
                                     ],
                                     glooms: [(700, 16)]),
                        pull: (dx: -70, dy: -14), abilityDelay: 0.45)
        case .twinkle:
            // Split at apex over two perches: one star becomes two.
            AbilityDemo(level: stage(character,
                                     pieces: [
                                         piece(.column, .moonwood, 600, 45),
                                         piece(.column, .moonwood, 720, 45),
                                     ],
                                     glooms: [(600, 106), (720, 106)]),
                        pull: (dx: -56, dy: -50), abilityDelay: 0.55)
        case .nox:
            // A sealed frame-roofed vault: only the well opens it.
            AbilityDemo(level: stage(character,
                                     pieces: [
                                         piece(.column, .meteorstone, 620, 45),
                                         piece(.column, .meteorstone, 720, 45),
                                         piece(.plank, .frame, 670, 102),
                                     ],
                                     glooms: [(670, 16)]),
                        pull: (dx: -50, dy: -56), abilityDelay: 0.85)
        case .misty:
            // A wood wall she has no business passing — and does.
            AbilityDemo(level: stage(character,
                                     pieces: [
                                         piece(.column, .moonwood, 640, 45),
                                         piece(.column, .moonwood, 640, 134),
                                     ],
                                     glooms: [(700, 16)]),
                        pull: (dx: -64, dy: -30), abilityDelay: 0.5)
        }
    }

    private static func piece(_ shape: PieceShape, _ material: Material,
                              _ x: Double, _ y: Double) -> MoonshotLevel.Piece {
        .init(shape: shape, material: material, x: x, y: y, rotation: 0)
    }

    private static func stage(_ character: CharacterID,
                              pieces: [MoonshotLevel.Piece],
                              glooms: [(Double, Double)]) -> MoonshotLevel {
        MoonshotLevel(schemaVersion: 1,
                      id: UUID(),
                      kind: .campaign, authorID: nil,
                      createdAt: .now, updatedAt: .now, deletedAt: nil,
                      title: nil,
                      par: 1,
                      queue: [character, character, character],
                      buildZone: .init(x: 500, y: 0, width: 320, height: 340),
                      pieces: pieces,
                      glooms: glooms.map { .init(x: $0.0, y: $0.1) })
    }
}
