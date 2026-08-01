import Foundation

/// The one level document (module doc: "the foundation piece"): campaign
/// levels, editor output, and 1v1 bases are all this shape — bundled JSON now,
/// synced records in slice (d), so the §7 hygiene fields (stable UUID,
/// updatedAt, authorID, tombstone) are here from day one.

enum CharacterID: String, Codable, CaseIterable {
    case mochi, zip, twinkle, nox, misty
}

enum Material: String, Codable, CaseIterable {
    case crystal, moonwood, meteorstone, cloudfoam, frame
}

enum PieceShape: String, Codable, CaseIterable {
    case square, plank, column, block
}

enum LevelKind: String, Codable {
    case campaign, custom, base
}

enum PlayMode: String, Codable {
    case solo, coop, assist
}

struct MoonshotLevel: Codable, Equatable, Identifiable {
    var schemaVersion: Int
    var id: UUID
    var kind: LevelKind
    var authorID: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    /// User data for custom/base levels — never translated (S6 spirit).
    /// Campaign titles are localized strings keyed by index, not stored here.
    var title: String?
    var par: Int
    /// The sprite lineup is part of the level design.
    var queue: [CharacterID]
    var buildZone: Zone
    var pieces: [Piece]
    var glooms: [GloomPlacement]
    /// a2: which world this level belongs to; nil = world 1 (v1 files
    /// decode unchanged — schemaVersion stays 1, both fields optional).
    var world: Int?
    /// a2: authored wind zones — constant force fields that bend flight
    /// arcs; the engine masks them to affect ONLY flying sprites (M21).
    var wind: [WindZone]?

    var worldNumber: Int { world ?? 1 }

    static let currentSchemaVersion = 1

    struct Zone: Codable, Equatable {
        var x, y, width, height: Double
    }

    /// `x`/`y` are the piece's center, in points, y up from the ground top.
    struct Piece: Codable, Equatable {
        var shape: PieceShape
        var material: Material
        var x, y, rotation: Double
    }

    struct GloomPlacement: Codable, Equatable {
        var x, y: Double
        /// The gloom's power (M29); absent = the classic gloom every
        /// shipped level was certified against.
        var kind: GloomKind?

        init(x: Double, y: Double, kind: GloomKind? = nil) {
            self.x = x
            self.y = y
            self.kind = kind
        }
    }
}

/// A gloom variant (M29): shield wears a crackable shell, hopper dodges,
/// mist answers only to powers, great is the boss.
enum GloomKind: String, Codable {
    case shield, hopper, mist, great
}

/// A constant-force region (M21): rect in level coordinates (y up from the
/// ground top), force in m/s² — the same unit family as the gravity knob.
struct WindZone: Codable, Equatable {
    var x, y, width, height: Double
    var forceX, forceY: Double
}

extension MoonshotLevel {

    var totalCost: Int {
        pieces.reduce(0) { $0 + $1.cost }
    }

    enum BaseInvalidity: Equatable {
        case overBudget(cost: Int)
        case framePieces
        case gloomCount(Int)
        case outsideZone
    }

    /// nil = a valid 1v1 base (M8: identical budget, no frames, exactly
    /// `baseGloomCount` hearts, everything inside the shared zone).
    func baseInvalidity(budget: Int) -> BaseInvalidity? {
        if pieces.contains(where: { $0.material == .frame }) { return .framePieces }
        if glooms.count != MoonshotTuning.baseGloomCount { return .gloomCount(glooms.count) }
        // Zone checks use the unrotated bounding box — rotation is ignored
        // for v1 (the editor snaps rotations; a rotated piece's footprint
        // never exceeds its diagonal, and the budget is the real fairness lever).
        for piece in pieces {
            let size = piece.shape.size
            if piece.x - Double(size.width) / 2 < buildZone.x
                || piece.x + Double(size.width) / 2 > buildZone.x + buildZone.width
                || piece.y - Double(size.height) / 2 < buildZone.y
                || piece.y + Double(size.height) / 2 > buildZone.y + buildZone.height {
                return .outsideZone
            }
        }
        let cost = totalCost
        if cost > budget { return .overBudget(cost: cost) }
        return nil
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// sortedKeys keeps committed campaign JSON diffs stable.
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension PieceShape {
    /// Points. The catalog is deliberately tiny (M7): a handful of shapes ×
    /// three materials is the whole building vocabulary.
    var size: CGSize {
        switch self {
        case .square: CGSize(width: 44, height: 44)
        case .plank: CGSize(width: 132, height: 22)
        case .column: CGSize(width: 22, height: 88)
        case .block: CGSize(width: 88, height: 88)
        }
    }

    var sizeUnits: Int {
        switch self {
        case .square: 1
        case .plank: 2
        case .column: 2
        case .block: 4
        }
    }
}

extension Material {
    /// The single value model (M7): crystal is cheap and brittle, meteorstone
    /// dear and tough; frames cost nothing because bases can't use them.
    var costMultiplier: Int {
        switch self {
        case .crystal: 1
        case .moonwood: 2
        case .meteorstone: 4
        case .cloudfoam: 3   // bounce is strong 1v1 defense — priced accordingly
        case .frame: 0
        }
    }
}

extension MoonshotLevel.Piece {
    /// One number, three jobs (M7): prices the 1v1 build budget now and sets
    /// demolition-point values in slice (c).
    var cost: Int {
        shape.sizeUnits * material.costMultiplier
    }
}
