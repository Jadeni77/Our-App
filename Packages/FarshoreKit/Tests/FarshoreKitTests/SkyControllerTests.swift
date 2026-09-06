import Foundation
import SceneKit
import Testing
import UIKit
@testable import FarshoreKit

/// **This file exists because it did not.**
///
/// `SkyController` had no tests at all, which meant the two single-sourcing
/// fixes already made on this branch — `duskFraction` moved to `SessionClock`,
/// `sunPeakIntensity` moved to `IslandLook` — had no regression cover
/// whatsoever: putting a literal back in this file failed nothing, and the
/// silent-revert bug they were fixed for would simply return. A fix with no
/// test is a fix with a half-life.
///
/// So the expectations below are written **in terms of the named constants**,
/// never against the numbers those constants currently hold. That is the
/// property under test. If someone changes `SessionClock.duskFraction` and
/// `SkyController` still reads it, everything here stays green; if someone
/// re-hardcodes `0.72` here, the sky and the clock disagree about when dark is
/// dark and these tests say so.
struct SkyControllerTests {
    /// Named `makeScene` rather than `scene` so the destructuring call sites
    /// below do not shadow it mid-statement.
    private func makeScene() -> (SCNScene, SCNNode) {
        let scene = SCNScene()
        IslandLook.configure(scene: scene, bundle: .module)
        let sun = IslandLook.makeSun()
        return (scene, sun)
    }

    private var daySky: Any? { IslandLook.daySkyBackground(in: .module) }

    /// `SCNScene.lightingEnvironment.intensity` is a `CGFloat` in the API and a
    /// `Float` in SceneKit's storage, so a value written as 0.12 reads back as
    /// 0.11999999731779099. Exact equality here fails on the round trip, not on
    /// anything anyone did wrong. The tolerance is far tighter than any
    /// plausible retune, so a genuinely different value still fails.
    private func expectIntensity(_ actual: CGFloat, _ expected: CGFloat,
                                 sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(actual - expected) < 0.000_01, sourceLocation: sourceLocation)
    }

    // MARK: - sunIntensity

    /// Noon is the midpoint of the daylight half, and it is `IslandLook`'s
    /// number — the ceiling of the curve and `makeSun()`'s initial intensity
    /// have to be the same value, or the first tick silently reverts a retune
    /// of the sun.
    @Test func theSunPeaksAtTheBrightnessIslandLookDeclares() {
        let noon = SessionClock.duskFraction / 2
        #expect(SkyController.sunIntensity(timeOfDay: noon) == IslandLook.sunPeakIntensity)
        #expect(IslandLook.makeSun().light?.intensity == IslandLook.sunPeakIntensity)
    }

    /// Night is lit by the environment alone — the sun is *off*, not merely
    /// dim, which is the premise slice 2's fire is built on.
    @Test func theSunIsOffAtNight() {
        #expect(SkyController.sunIntensity(timeOfDay: SessionClock.duskFraction) == 0)
        #expect(SkyController.sunIntensity(timeOfDay: SessionClock.duskFraction + 0.01) == 0)
        #expect(SkyController.sunIntensity(timeOfDay: 0.999) == 0)
    }

    /// The comment on `sunIntensity` claims it "fades in and out at the ends
    /// rather than snapping on". Continuity at the dusk boundary is what makes
    /// that true, and it is the half a constant-brightness sun would break:
    /// the guard would still return 0 at dusk, but the last lit frame before
    /// it would be full noon brightness and the sun would go out like a
    /// light switch.
    @Test func theSunFadesIntoDuskRatherThanSnappingOff() {
        let justBefore = SkyController.sunIntensity(timeOfDay: SessionClock.duskFraction - 0.0001)
        #expect(justBefore > 0)
        #expect(justBefore < IslandLook.sunPeakIntensity * 0.01)

        // Dawn is the same story at the other end.
        let justAfterDawn = SkyController.sunIntensity(timeOfDay: 0.0001)
        #expect(justAfterDawn > 0)
        #expect(justAfterDawn < IslandLook.sunPeakIntensity * 0.01)
        #expect(SkyController.sunIntensity(timeOfDay: 0) == 0)
    }

    // MARK: - sunEuler

    /// −10° at dawn through −170° at dusk: a low raking angle at both ends,
    /// because that is where terrain relief reads. Both ends are pinned, so
    /// "the sun crosses the sky" cannot quietly become "the sun sits still".
    @Test func theSunSweepsFromHorizonToHorizonAcrossTheDaylightHalf() {
        let dawn = SkyController.sunEuler(timeOfDay: 0)
        let dusk = SkyController.sunEuler(timeOfDay: SessionClock.duskFraction)
        #expect(abs(Double(dawn.x) - (-10.0 * .pi / 180.0)) < 0.0001)
        #expect(abs(Double(dusk.x) - (-170.0 * .pi / 180.0)) < 0.0001)
        // A fixed yaw: the sun rises in the same quarter of the sky every day.
        #expect(dawn.y == dusk.y)
    }

    /// **The clamp.** `timeOfDay` runs to 1.0 but the sweep is defined only
    /// over the daylight half, so without `clamped(to: 0...1)` the sun keeps
    /// rotating through the night — past −232° by the end of the cycle, i.e.
    /// back up above the horizon, casting shadows across a scene that is
    /// supposed to be dark. `sunIntensity` returning 0 hides it from the
    /// lighting but not from anything later that reads the sun's direction.
    @Test func theSunHoldsAtDuskInsteadOfRotatingThroughTheNight() {
        let dusk = SkyController.sunEuler(timeOfDay: SessionClock.duskFraction)
        for nightTime in [SessionClock.duskFraction + 0.0001, 0.85, 0.999, 1.0] {
            let held = SkyController.sunEuler(timeOfDay: nightTime)
            #expect(held.x == dusk.x)
            #expect(held.y == dusk.y)
            #expect(held.z == dusk.z)
        }
    }

    // MARK: - apply

    /// **F2, as a test.** `IslandLook.configure` sets the daylight sky once;
    /// `SCNMaterialProperty.intensity` does not modulate a background; so
    /// until `apply` took ownership of it, every session spent its last 5.6
    /// minutes showing dark terrain and near-black fog under a bright blue
    /// midday sky. The round trip is the assertion — going dark is only half
    /// the job, and a night sky that never lifts is the same bug rotated.
    @Test func nightChangesTheSkyAndDawnPutsItBack() {
        let (scene, sun) = makeScene()
        let noon = SessionClock.duskFraction / 2

        SkyController.apply(timeOfDay: noon, sun: sun, scene: scene, daySky: daySky)
        #expect(scene.background.contents as? URL == daySky as? URL)

        SkyController.apply(timeOfDay: 0.9, sun: sun, scene: scene, daySky: daySky)
        #expect(scene.background.contents as? UIColor == IslandLook.nightSkyColor)

        SkyController.apply(timeOfDay: noon, sun: sun, scene: scene, daySky: daySky)
        #expect(scene.background.contents as? URL == daySky as? URL)
    }

    /// Fog, environment and sky have to change together or the scene reads as
    /// broken rather than as dark — and each is a value `IslandLook` owns and
    /// this file only references. Asserting against the constants (not against
    /// `0.12` and `UIColor(white: 0.10)`) is what makes re-hardcoding them
    /// here a failing test rather than a silent revert.
    @Test func nightDimsTheEnvironmentAndTheFogFromIslandLooksConstants() {
        let (scene, sun) = makeScene()
        SkyController.apply(timeOfDay: 0.9, sun: sun, scene: scene, daySky: daySky)
        expectIntensity(scene.lightingEnvironment.intensity, IslandLook.nightEnvironmentIntensity)
        #expect(scene.fogColor as? UIColor == IslandLook.nightFogColor)
        #expect(sun.light?.intensity == 0)
    }

    @Test func dayRestoresTheEnvironmentAndTheFogFromIslandLooksConstants() {
        let (scene, sun) = makeScene()
        // Go through night first, so this proves restoration rather than
        // merely that `configure` already left the right values in place.
        SkyController.apply(timeOfDay: 0.9, sun: sun, scene: scene, daySky: daySky)
        SkyController.apply(timeOfDay: SessionClock.duskFraction / 2,
                            sun: sun, scene: scene, daySky: daySky)
        expectIntensity(scene.lightingEnvironment.intensity, IslandLook.dayEnvironmentIntensity)
        #expect(scene.fogColor as? UIColor == IslandLook.dayFogColor)
        #expect(sun.light?.intensity == IslandLook.sunPeakIntensity)
    }

    /// The sky must flip on the *same* frame the clock calls night, not one
    /// side of the boundary early or late. `duskFraction` is inclusive: at
    /// exactly `duskFraction`, `SessionClock.isNight` is already true.
    ///
    /// This is the assertion that fails if a literal `0.72` comes back here
    /// and `SessionClock.duskFraction` later moves: it compares the sky's
    /// behaviour against the clock's own answer, not against a number.
    @Test func theSkyFlipsExactlyWhenTheClockSaysNight() {
        let (scene, sun) = makeScene()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = SessionClock(startedAt: start)

        for fraction in [0.0, 0.25, 0.5, SessionClock.duskFraction - 0.001,
                         SessionClock.duskFraction, 0.8, 0.99] {
            let now = start.addingTimeInterval(SessionClock.dayLength * fraction)
            SkyController.apply(timeOfDay: clock.timeOfDay(at: now),
                                sun: sun, scene: scene, daySky: daySky)
            let skyIsNight = scene.background.contents is UIColor
            #expect(skyIsNight == clock.isNight(at: now))
        }
    }

    /// `apply` runs on every frame, so it has to be safe to run on every
    /// frame: repeating it must not accumulate anything or re-assign the
    /// background, which would ask SceneKit to re-decode a 4.6 MB Radiance
    /// image 30 times a second. Object identity of the background is the
    /// observable proxy for "was not re-assigned".
    @Test func repeatedTicksAtTheSameTimeChangeNothing() {
        let (scene, sun) = makeScene()
        let noon = SessionClock.duskFraction / 2
        SkyController.apply(timeOfDay: noon, sun: sun, scene: scene, daySky: daySky)
        let firstAngles = sun.eulerAngles
        let firstIntensity = sun.light?.intensity

        for _ in 0..<30 {
            SkyController.apply(timeOfDay: noon, sun: sun, scene: scene, daySky: daySky)
        }
        #expect(sun.eulerAngles.x == firstAngles.x)
        #expect(sun.light?.intensity == firstIntensity)
        #expect(scene.background.contents as? URL == daySky as? URL)
    }
}
