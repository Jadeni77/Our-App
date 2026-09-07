import Foundation

/// Which way the character is pointing, and how it catches up with where it
/// is actually walking.
///
/// Pure — no SceneKit, no UIKit (`Rules/` is PURE, P39's extraction boundary
/// again: a rotation formula does not need a scene graph to be correct, and
/// keeping it out of one means "it spun the wrong way round" is debuggable by
/// reading numbers, not by walking in circles on a phone.
public enum FacingRules {
    /// Radians per second. Fast enough that a direction change reads within a
    /// couple of frames; slow enough that the turn is visible as a turn
    /// rather than a snap — a character that snaps to a new facing every
    /// frame reads as broken (task brief).
    public static let turnRatePerSecond: Double = .pi * 3

    /// Turns `current` toward the direction of `towards`, at
    /// `turnRatePerSecond`, taking the shortest way round, and never
    /// overshooting the target within one step. Returns `current` unchanged
    /// when `towards` is the zero vector — standing still must not reset
    /// facing to due north.
    ///
    /// **The angle convention is `LocomotionRules`', restated here on
    /// purpose so the two files cannot quietly disagree.** `LocomotionRules`
    /// documents `FollowCamera`'s forward as `(sin heading, cos heading)` in
    /// world `(x, z)`, and derives strafe from that pair explicitly rather
    /// than assuming it. `towards` here is fed the player's own per-frame
    /// movement delta — the same `(x, z)` displacement `LocomotionRules`
    /// hands back — so the target angle that makes
    /// `(sin target, cos target) == normalize(towards)` is
    /// `atan2(towards.x, towards.y)`: **`x` first**, matching `sin` first in
    /// that pair, not the `atan2(y, x)` a reader might paste in from habit
    /// (screen-space or map-heading code usually wants the other order).
    ///
    /// Getting this backwards would be the **third** sign/rotation bug in
    /// this project — slice 1 already shipped an inverted strafe axis and a
    /// turn gesture that integrated a cumulative drag offset, and both
    /// survived several reviews because the code still ran and still turned,
    /// just wrongly. Swapping the two arguments here compiles, still turns
    /// smoothly, and takes the shortest way round — it would just make the
    /// character face 90° off from the way it is walking, silently, forever.
    public static func face(current: Double, towards: SIMD2<Double>, dt: Double) -> Double {
        guard towards.x != 0 || towards.y != 0 else { return current }
        let target = atan2(towards.x, towards.y)

        // Shortest way round: wrap the raw difference into (-pi, pi] before
        // applying any rate limit. Without this, turning from just-under
        // +pi to just-over -pi (a hair's turn) computes as a turn of nearly
        // -2*pi (almost a full circle the long way), and the character
        // visibly spins on the spot instead of nudging across the seam.
        var delta = target - current
        while delta > .pi { delta -= 2 * .pi }
        while delta <= -.pi { delta += 2 * .pi }

        // Clamping the STEP to at most `delta` in magnitude (via min/max
        // against `±maxStep`) is what makes "never overshoots" true: `delta`
        // is already the exact signed distance to the target, so taking any
        // step no larger than it in the same direction can only land at or
        // short of the target, never past it. A naive version that instead
        // always steps by the full `turnRatePerSecond * dt` — rather than
        // capping it at the remaining `delta` — flies past the target the
        // moment the allowed step exceeds what's left to turn (e.g. a large
        // `dt` after a frame hitch), and then oscillates around it forever.
        let maxStep = turnRatePerSecond * dt
        let step = max(-maxStep, min(maxStep, delta))
        return current + step
    }
}
