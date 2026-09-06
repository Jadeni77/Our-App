import Foundation

/// How input becomes movement. Pure, so it can be tested without a scene.
public enum LocomotionRules {
    /// Metres per second. A 512 m island is then ~3 minutes corner to corner,
    /// which is the "crossable in a couple of minutes" the design asks for.
    public static let walkSpeed: Double = 2.8

    /// Input is `(x: strafe, y: forward)` in the range −1…1.
    ///
    /// **Clamped to a unit disc, never normalised unconditionally.** Normalising
    /// every input would turn a thumb half-over into a full-speed run; leaving
    /// it unclamped would make diagonal movement √2 times faster than straight,
    /// which quietly makes running diagonally the correct way to play.
    public static func displacement(input: SIMD2<Double>, heading: Double, dt: Double) -> SIMD2<Double> {
        let length = sqrt(input.x * input.x + input.y * input.y)
        guard length > 0 else { return SIMD2(0, 0) }
        let scaled = length > 1 ? input / length : input

        let cosine = cos(heading), sine = sin(heading)
        let worldX = scaled.x * cosine + scaled.y * sine
        let worldZ = -scaled.x * sine + scaled.y * cosine
        return SIMD2(worldX * walkSpeed * dt, worldZ * walkSpeed * dt)
    }

    /// Uphill costs speed; downhill is free but never a bonus.
    ///
    /// Downhill deliberately does not speed you up: it would make the fastest
    /// route across the island a series of descents, and reward a kind of
    /// movement nobody is trying to encourage.
    public static func slopeFactor(from: Double, to: Double, over distance: Double) -> Double {
        guard distance > 0 else { return 1 }
        let gradient = (to - from) / distance
        guard gradient > 0 else { return 1 }
        return max(0.1, 1 - gradient * 0.9)
    }
}
