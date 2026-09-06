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
        let sweep = (timeOfDay / SessionClock.duskFraction).clamped(to: 0...1)
        let pitch = -(10.0 + sweep * 160.0) * .pi / 180.0
        return SCNVector3(Float(pitch), Float(-0.6), 0)
    }

    public static func sunIntensity(timeOfDay: Double) -> CGFloat {
        guard timeOfDay < SessionClock.duskFraction else { return 0 }
        // Fades in and out at the ends rather than snapping on.
        let sweep = timeOfDay / SessionClock.duskFraction
        // Peak brightness is `IslandLook.makeSun()`'s decision, not this
        // file's — referencing it here (rather than repeating `2_400`) is
        // what keeps `apply`'s per-tick overwrite of `light.intensity` from
        // silently reverting a change made in `makeSun()` a frame later.
        return CGFloat(sin(sweep * .pi)) * IslandLook.sunPeakIntensity
    }

    /// Drives the whole sky from the time of day.
    ///
    /// **Every value written here is `IslandLook`'s decision, referenced, not
    /// this file's, repeated.** That is not style: this function overwrites
    /// each of these properties on every tick, so a literal here would mean a
    /// retune in `IslandLook` — the file whose stated job is holding how the
    /// island looks — silently reverting one frame later, with no error and
    /// nothing to grep for. The branch was bitten by exactly this three times
    /// (`textureScale`, `sunPeakIntensity`, `duskFraction`) before the fog and
    /// the environment intensity were found to be doing it too.
    ///
    /// `daySky` is passed in rather than resolved here because resolving it
    /// means a bundle lookup and, on assignment, decoding a 4.6 MB Radiance
    /// image — per frame, at 30 Hz. `IslandLook.daySkyBackground(in:)` is the
    /// single source; the caller holds the result for the session.
    public static func apply(timeOfDay: Double, sun: SCNNode, scene: SCNScene, daySky: Any?) {
        sun.eulerAngles = sunEuler(timeOfDay: timeOfDay)
        sun.light?.intensity = sunIntensity(timeOfDay: timeOfDay)
        // `duskFraction` is `SessionClock`'s call, not this file's — see the
        // comment there on why the sky and the clock must not disagree about
        // when dark is dark.
        let night = timeOfDay >= SessionClock.duskFraction
        scene.lightingEnvironment.intensity = night ? IslandLook.nightEnvironmentIntensity
                                                    : IslandLook.dayEnvironmentIntensity
        scene.fogColor = night ? IslandLook.nightFogColor : IslandLook.dayFogColor

        // **The background has to move too, and nothing else will move it.**
        // `IslandLook.configure` sets the daylight sky once and never again,
        // and `SCNMaterialProperty.intensity` does *not* modulate a
        // background, so before this existed the terrain and the fog went dark
        // at dusk under a bright blue midday sky — 14.4 minutes into every
        // session, for the last 5.6 minutes of the cycle. Owning it here, next
        // to the fog and the environment intensity it has to agree with, is
        // the only arrangement where those three cannot drift apart.
        //
        // Assign only on the *transition*, never per frame: `contents` is a
        // texture slot, and handing it the `.hdr` URL again 30 times a second
        // asks SceneKit to re-decode the sky 30 times a second. Which sky is
        // currently up is readable from the slot itself — day is a `URL`,
        // night is a `UIColor` — so there is no extra stored state, and
        // therefore no stored state that can fall out of sync with the scene
        // it claims to describe. If the day sky ever becomes a `UIColor` too,
        // this test stops working and needs replacing with an explicit flag.
        let nightSkyIsUp = scene.background.contents is UIColor
        if nightSkyIsUp != night {
            scene.background.contents = night ? IslandLook.nightSkyColor : daySky
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
