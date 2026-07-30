import Foundation

/// While a tile drag is live the pager's own swipe is disabled, so this is
/// how a tile travels between pages (S8): holding the finger against a
/// screen edge flips to the neighboring page. The dwell keeps a drag that
/// merely skims an edge from flipping; keep holding and it fires again each
/// dwell — one page per beat, like the real springboard.
struct EdgeFlipDetector {
    enum Direction {
        case back, forward
    }

    static let dwell: TimeInterval = 0.35
    static let zoneWidth: CGFloat = 44

    private var armed: (direction: Direction, since: Date)?

    /// Feed every drag location; returns a direction exactly when a flip
    /// should happen.
    mutating func update(x: CGFloat, width: CGFloat, now: Date) -> Direction? {
        let direction: Direction? = if x <= Self.zoneWidth {
            .back
        } else if x >= width - Self.zoneWidth {
            .forward
        } else {
            nil
        }
        guard let direction else {
            armed = nil
            return nil
        }
        guard let armed, armed.direction == direction else {
            self.armed = (direction, now)
            return nil
        }
        guard now.timeIntervalSince(armed.since) >= Self.dwell else { return nil }
        self.armed = (direction, now)   // hold to keep flipping, page per beat
        return direction
    }

    /// A new drag starts with a clean slate.
    mutating func reset() {
        armed = nil
    }
}
