import CoreGraphics
import Foundation

/// Where one body was, at one sampled moment.
struct BodyPose: Equatable {
    var x: Double
    var y: Double
    /// Radians. Normalised into `[0, 2π)` on encode.
    var angle: Double
}

/// A recording of one fling: every moving body's pose, sampled over the couple
/// of seconds it lasts.
///
/// **A fling travels as a recording, not as inputs to re-simulate.** SpriteKit's
/// physics is Box2D, and it does not produce identical results across different
/// devices — same inputs, quietly different outcomes. In a destruction game
/// that is the worst case: a millimetre of divergence early becomes a different
/// pile of rubble. So her phone plays back exactly what she saw.
struct FlingClip: Equatable {
    var frameRate: Int
    /// Fixed for the whole clip; frames index into this.
    var bodyIDs: [String]
    var frames: [Frame]

    struct Frame: Equatable {
        var poses: [BodyPose]
        /// Which bodies still exist this frame. **Not decoration** — pieces get
        /// destroyed mid-fling, and without this they would freeze in place on
        /// the watching phone instead of vanishing.
        var present: [Bool]
    }

    var duration: TimeInterval {
        frameRate > 0 ? Double(frames.count) / Double(frameRate) : 0
    }
}

/// Packs a clip small enough to travel with a record.
///
/// Sizing, so this is a decision rather than a hope: 40 bodies × 60 frames costs
/// about 15KB — smaller than one of the photos already syncing. If it ever runs
/// large, the frame rate is the dial; 20Hz is invisible in a replay.
enum FlingClipCodec {
    private static let magic: [UInt8] = [0x46, 0x43]   // "FC"
    private static let version: UInt8 = 1
    /// Positions are quantised to 1/`scale` of a point. 4 gives quarter-point
    /// precision and a ±8191 point range, which is far beyond any level.
    static let scale: Double = 4

    static func encode(_ clip: FlingClip) -> Data {
        var out = Data(magic)
        out.append(version)
        out.append(UInt8(clamping: clip.frameRate))
        out.append(uint16: UInt16(clamping: clip.bodyIDs.count))
        out.append(uint16: UInt16(clamping: clip.frames.count))

        for id in clip.bodyIDs {
            let bytes = Array(id.utf8.prefix(255))
            out.append(UInt8(bytes.count))
            out.append(contentsOf: bytes)
        }

        let presenceBytes = (clip.bodyIDs.count + 7) / 8
        for frame in clip.frames {
            var bits = [UInt8](repeating: 0, count: presenceBytes)
            for (index, alive) in frame.present.enumerated() where alive {
                bits[index / 8] |= UInt8(1 << (index % 8))
            }
            out.append(contentsOf: bits)
            for pose in frame.poses {
                out.append(int16: Int16(clamping: Int(( pose.x * scale).rounded())))
                out.append(int16: Int16(clamping: Int((pose.y * scale).rounded())))
                out.append(uint16: quantise(angle: pose.angle))
            }
        }
        return out
    }

    static func decode(_ data: Data) -> FlingClip? {
        var cursor = data.startIndex
        func take(_ count: Int) -> Data? {
            guard data.distance(from: cursor, to: data.endIndex) >= count else { return nil }
            defer { cursor = data.index(cursor, offsetBy: count) }
            return data[cursor..<data.index(cursor, offsetBy: count)]
        }
        guard let head = take(4), Array(head.prefix(2)) == magic,
              head[head.index(head.startIndex, offsetBy: 2)] == version
        else { return nil }
        let frameRate = Int(head[head.index(head.startIndex, offsetBy: 3)])
        guard let counts = take(4) else { return nil }
        let bodyCount = Int(counts.uint16(at: 0))
        let frameCount = Int(counts.uint16(at: 2))

        var bodyIDs: [String] = []
        for _ in 0..<bodyCount {
            guard let lengthByte = take(1), let bytes = take(Int(lengthByte[lengthByte.startIndex]))
            else { return nil }
            bodyIDs.append(String(decoding: bytes, as: UTF8.self))
        }

        let presenceBytes = (bodyCount + 7) / 8
        var frames: [FlingClip.Frame] = []
        for _ in 0..<frameCount {
            guard let bits = take(presenceBytes), let body = take(bodyCount * 6) else { return nil }
            let bitArray = Array(bits)
            var present: [Bool] = []
            var poses: [BodyPose] = []
            for index in 0..<bodyCount {
                present.append(bitArray[index / 8] & UInt8(1 << (index % 8)) != 0)
                let base = index * 6
                poses.append(BodyPose(x: Double(body.int16(at: base)) / scale,
                                      y: Double(body.int16(at: base + 2)) / scale,
                                      angle: dequantise(angle: body.uint16(at: base + 4))))
            }
            frames.append(FlingClip.Frame(poses: poses, present: present))
        }
        return FlingClip(frameRate: frameRate, bodyIDs: bodyIDs, frames: frames)
    }

    private static func quantise(angle: Double) -> UInt16 {
        let turn = 2 * Double.pi
        let wrapped = angle.truncatingRemainder(dividingBy: turn)
        let positive = wrapped < 0 ? wrapped + turn : wrapped
        return UInt16((positive / turn * 65536).rounded()) & 0xFFFF
    }

    private static func dequantise(angle: UInt16) -> Double {
        Double(angle) / 65536 * 2 * Double.pi
    }
}

private extension Data {
    mutating func append(uint16 value: UInt16) {
        append(UInt8(value >> 8)); append(UInt8(value & 0xFF))
    }
    mutating func append(int16 value: Int16) {
        append(uint16: UInt16(bitPattern: value))
    }
    func uint16(at offset: Int) -> UInt16 {
        let start = index(startIndex, offsetBy: offset)
        return UInt16(self[start]) << 8 | UInt16(self[index(after: start)])
    }
    func int16(at offset: Int) -> Int16 {
        Int16(bitPattern: uint16(at: offset))
    }
}
