import Foundation

/// Time of day, scoped to this session (F3).
///
/// **Nothing here is ever persisted, and that is the whole point.** Survival is
/// the one loop where time passing while you are away hurts you, and this
/// island is async by construction — a partner's busy week must not be damage
/// to your island, and in group mode the least-active member's schedule must
/// not set everyone's losses. So: open the app and it is dawn.
///
/// Crops are the deliberate exception and they derive from `plantedAt`, not
/// from this. Growth is safe to hand to a timestamp; decay is not.
public struct SessionClock: Sendable, Equatable {
    /// One full cycle. Long enough for dusk to mean something, short enough
    /// that surviving a night is one sitting.
    public static let dayLength: TimeInterval = 20 * 60

    public let startedAt: Date

    public init(startedAt: Date = Date()) {
        self.startedAt = startedAt
    }

    /// 0 = dawn, 0.5 = midday, 1 → wraps back to dawn.
    public func timeOfDay(at now: Date) -> Double {
        let elapsed = now.timeIntervalSince(startedAt)
        let phase = elapsed.truncatingRemainder(dividingBy: Self.dayLength)
        // A negative interval means somebody asked about a moment before the
        // session began. Wrapping keeps it in range rather than returning a
        // negative time of day nothing downstream expects.
        return (phase < 0 ? phase + Self.dayLength : phase) / Self.dayLength
    }

    public func isNight(at now: Date) -> Bool {
        timeOfDay(at: now) >= 0.72
    }
}
