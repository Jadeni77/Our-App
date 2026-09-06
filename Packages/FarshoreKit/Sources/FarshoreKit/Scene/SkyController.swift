import Foundation
import SceneKit
import UIKit

/// Turns a time of day into a sky.
public enum SkyController {
    /// The sun swings from horizon to horizon over the daylight half. Kept as
    /// a pure function of `timeOfDay` so the scene never becomes the authority
    /// on what time it is — `SessionClock` is.
    public static func sunEuler(timeOfDay: Double) -> SCNVector3 {
        // -10° at dawn through -170° at dusk: a low raking angle at both ends,
        // which is where terrain reads best.
        let sweep = (timeOfDay / 0.72).clamped(to: 0...1)
        let pitch = -(10.0 + sweep * 160.0) * .pi / 180.0
        return SCNVector3(Float(pitch), Float(-0.6), 0)
    }

    public static func sunIntensity(timeOfDay: Double) -> CGFloat {
        guard timeOfDay < 0.72 else { return 0 }
        // Fades in and out at the ends rather than snapping on.
        let sweep = timeOfDay / 0.72
        // Peak brightness is `IslandLook.makeSun()`'s decision, not this
        // file's — referencing it here (rather than repeating `2_400`) is
        // what keeps `apply`'s per-tick overwrite of `light.intensity` from
        // silently reverting a change made in `makeSun()` a frame later.
        return CGFloat(sin(sweep * .pi)) * IslandLook.sunPeakIntensity
    }

    public static func apply(timeOfDay: Double, sun: SCNNode, scene: SCNScene) {
        sun.eulerAngles = sunEuler(timeOfDay: timeOfDay)
        sun.light?.intensity = sunIntensity(timeOfDay: timeOfDay)
        // Night is lit by the environment alone, dimmed — which is what makes
        // fire matter later (slice 2) without anything here knowing about fire.
        let night = timeOfDay >= 0.72
        scene.lightingEnvironment.intensity = night ? 0.12 : 1.0
        scene.fogColor = night ? UIColor(white: 0.10, alpha: 1)
                               : UIColor(white: 0.72, alpha: 1)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
