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

    /// The fraction of the cycle at which day ends and night begins.
    ///
    /// Declared once, here, because it is a rule (when night falls) rather
    /// than a rendering detail — `SkyController` reads it rather than
    /// carrying its own copy. The two must move together: `SkyController`
    /// uses this same fraction to decide the sun's fade-out point, the
    /// lighting environment's night dimming, and the fog colour switch, so a
    /// second literal there would let the sky and the clock disagree about
    /// when dark is dark — the sun could keep shining after `isNight`
    /// already says it hasn't.
    public static let duskFraction: Double = 0.72

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
        timeOfDay(at: now) >= Self.duskFraction
    }

    /// Skips the day past time nobody was playing.
    ///
    /// **This is what makes F3 true rather than merely intended.** The
    /// clock is anchored to a real instant, so left alone it keeps running
    /// through a backgrounded app: play five minutes of a twenty-minute
    /// day, take a twelve-minute phone call, come back past dusk, and
    /// warmth is now draining at 2.5× because of time you spent away. The
    /// render loop already refuses to charge a need for that gap — it caps
    /// `dt` — and this is the same refusal applied to the day itself.
    ///
    /// Returns a new clock rather than mutating, because a `SessionClock`
    /// is a value and the only two things allowed to replace one are this
    /// and waking up dead.
    public func advancingStart(by seconds: TimeInterval) -> SessionClock {
        SessionClock(startedAt: startedAt.addingTimeInterval(seconds))
    }
}
