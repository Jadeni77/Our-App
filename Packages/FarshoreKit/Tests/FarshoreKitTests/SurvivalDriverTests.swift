import Foundation
import Testing
@testable import FarshoreKit

/// The seam between the pure rules and the world: a real player position, a
/// real clock, and `SurvivalState`/`ProximityRules`/`ForageField` all in one
/// place. Everything those three answer in isolation is already pinned by
/// their own test files; what is only pinned here is whether the driver asks
/// them the right questions and honours what they say back — in particular
/// that `take` can genuinely say no, and that no does not mean "did it
/// anyway."
struct SurvivalDriverTests {
    private let farAway = (x: 5_000.0, z: 5_000.0)

    @Test func steppingDrainsAllThreeNeeds() {
        let driver = SurvivalDriver(fire: (x: 0, z: 0), points: [], seaLevel: 0)
        driver.step(playerX: farAway.x, playerZ: farAway.z, playerHeight: 10,
                   dt: 60, isNight: false, now: Date())
        #expect(driver.state.water < 1)
        #expect(driver.state.food < 1)
        #expect(driver.state.warmth < 1)
    }

    /// `nearFire` has to actually reach `SurvivalRules.step` as `true` when
    /// the player is inside `ProximityRules.fireWarmthRadius` — this is the
    /// one fact `SurvivalRulesTests.theFireRestoresWarmth` cannot check on
    /// its own, since it calls `SurvivalRules.step` directly with `nearFire`
    /// already decided.
    @Test func standingAtTheFireWarmsYouBackUp() {
        let driver = SurvivalDriver(fire: (x: 0, z: 0), points: [], seaLevel: 0)
        let now = Date()
        // Cool off first, well away from the fire, so there is room to warm
        // back up and the assertion below is not testing a value already
        // pinned at 1.
        driver.step(playerX: farAway.x, playerZ: farAway.z, playerHeight: 10,
                   dt: 10_000, isNight: false, now: now)
        let cooled = driver.state.warmth
        #expect(cooled < 1)

        driver.step(playerX: 0, playerZ: 0, playerHeight: 10, dt: 30, isNight: false, now: now)
        #expect(driver.state.warmth > cooled)
    }

    /// `inSea` has to reach `SurvivalRules.step` too, and specifically from
    /// `ProximityRules.isInSea` comparing the player's height to the
    /// driver's own `seaLevel` — not from `isNight`, which this test holds
    /// equal on both sides so a driver that ignored height entirely, or that
    /// mixed the two flags up, cannot pass by accident.
    @Test func enteringTheSeaDrainsWarmthFasterThanDryLand() {
        let onLand = SurvivalDriver(fire: (x: 0, z: 0), points: [], seaLevel: 3)
        onLand.step(playerX: farAway.x, playerZ: farAway.z, playerHeight: 10,
                   dt: 60, isNight: false, now: Date())

        let inSea = SurvivalDriver(fire: (x: 0, z: 0), points: [], seaLevel: 3)
        inSea.step(playerX: farAway.x, playerZ: farAway.z, playerHeight: 1,
                  dt: 60, isNight: false, now: Date())

        #expect(inSea.state.warmth < onLand.state.warmth)
    }

    @Test func theOfferAppearsInReachAndClearsWhenYouWalkAway() {
        let berries = ForagePoint(id: 0, x: 10, z: 0, kind: .berries)
        let driver = SurvivalDriver(fire: (x: 0, z: 0), points: [berries], seaLevel: 0)
        let now = Date()

        driver.step(playerX: 10, playerZ: 0, playerHeight: 10, dt: 1, isNight: false, now: now)
        #expect(driver.offer?.id == berries.id)

        driver.step(playerX: farAway.x, playerZ: farAway.z, playerHeight: 10,
                   dt: 1, isNight: false, now: now)
        #expect(driver.offer == nil)
    }

    @Test func aPickedBushStopsBeingOffered() {
        let berries = ForagePoint(id: 0, x: 10, z: 0, kind: .berries)
        let driver = SurvivalDriver(fire: (x: 0, z: 0), points: [berries], seaLevel: 0)
        let now = Date()

        driver.step(playerX: 10, playerZ: 0, playerHeight: 10, dt: 1, isNight: false, now: now)
        #expect(driver.offer?.id == berries.id)
        #expect(driver.take(berries, now: now))

        // Still standing in the same spot — the bush itself has to be the
        // reason it is no longer offered, not distance.
        driver.step(playerX: 10, playerZ: 0, playerHeight: 10, dt: 1, isNight: false, now: now)
        #expect(driver.offer == nil)
    }

    /// The case the brief calls out by name: a bush that is not available
    /// must refuse, and refusing must be inert. Two `take` calls with no
    /// `step` in between, which is exactly what a fast double-tap on
    /// `ActionButton` (Task 6) would produce before the next frame runs.
    @Test func takingAnUnavailableBushFailsAndChangesNothing() {
        let berries = ForagePoint(id: 0, x: 10, z: 0, kind: .berries)
        let driver = SurvivalDriver(fire: (x: 0, z: 0), points: [berries], seaLevel: 0)
        let now = Date()

        driver.step(playerX: 10, playerZ: 0, playerHeight: 10, dt: 1, isNight: false, now: now)
        #expect(driver.take(berries, now: now))
        let stateAfterFirstTake = driver.state
        let pickedAtAfterFirstTake = driver.pickedAt

        #expect(driver.take(berries, now: now) == false)
        #expect(driver.state == stateAfterFirstTake)
        #expect(driver.pickedAt == pickedAtAfterFirstTake)
    }

    /// The other way `take` must refuse: nothing was ever offered, because
    /// the player was never in reach. Distinct from the test above — a
    /// driver that checked only `ForageField.isAvailable` and forgot the
    /// reach check would pass the unavailable-bush test above by refusing
    /// for the wrong reason, but would wrongly ACCEPT this one, since a
    /// never-picked bush is available by `ForageField`'s own rule.
    @Test func takingSomethingNeverOfferedFailsAndChangesNothing() {
        let berries = ForagePoint(id: 0, x: 10, z: 0, kind: .berries)
        let driver = SurvivalDriver(fire: (x: 0, z: 0), points: [berries], seaLevel: 0)
        let now = Date()
        let before = driver.state

        #expect(driver.take(berries, now: now) == false)
        #expect(driver.state == before)
        #expect(driver.pickedAt[berries.id] == nil)
    }

    @Test func takingBerriesRaisesFoodOnly() {
        let berries = ForagePoint(id: 0, x: 10, z: 0, kind: .berries)
        let driver = SurvivalDriver(fire: (x: 0, z: 0), points: [berries], seaLevel: 0)
        let now = Date()
        driver.step(playerX: 10, playerZ: 0, playerHeight: 10, dt: 1, isNight: false, now: now)
        let before = driver.state

        #expect(driver.take(berries, now: now))
        #expect(driver.state.food > before.food)
        #expect(driver.state.water == before.water)
        #expect(driver.state.warmth == before.warmth)
    }

    /// A spring is never exhausted — `ForageField.isAvailable` says yes for
    /// one regardless of `pickedAt`, and `take` deliberately never records a
    /// pick time for one (see the comment in `take`). Proven here by taking
    /// the same spring twice in a row, with a `step` in between so the offer
    /// is genuinely recomputed rather than merely stale.
    @Test func takingASpringNeverExhaustsIt() {
        let spring = ForagePoint(id: 0, x: 10, z: 0, kind: .spring)
        let driver = SurvivalDriver(fire: (x: 0, z: 0), points: [spring], seaLevel: 0)
        let now = Date()

        driver.step(playerX: 10, playerZ: 0, playerHeight: 10, dt: 1, isNight: false, now: now)
        #expect(driver.take(spring, now: now))
        #expect(driver.pickedAt[spring.id] == nil)

        driver.step(playerX: 10, playerZ: 0, playerHeight: 10, dt: 1, isNight: false, now: now)
        #expect(driver.offer?.id == spring.id)
        #expect(driver.take(spring, now: now))
    }

    /// **Dying must not restock the island.** `revive` returns the state to
    /// `.rested` and nothing else — the picked bush stays picked, or
    /// starving to death becomes a way to farm a stripped patch back to
    /// full, which is exactly backwards for a mechanic whose entire point is
    /// that death costs you something.
    @Test func reviveResetsStateButLeavesPickedBushesPicked() {
        let berries = ForagePoint(id: 0, x: 10, z: 0, kind: .berries)
        let driver = SurvivalDriver(fire: (x: 0, z: 0), points: [berries], seaLevel: 0)
        let now = Date()

        driver.step(playerX: 10, playerZ: 0, playerHeight: 10, dt: 1, isNight: false, now: now)
        #expect(driver.take(berries, now: now))
        #expect(driver.pickedAt[berries.id] != nil)

        // Starve to death: far from the fire, in the sea, at night, for a
        // very long time.
        driver.step(playerX: farAway.x, playerZ: farAway.z, playerHeight: -100,
                   dt: 1_000_000, isNight: true, now: now)
        #expect(driver.state.isDead)

        driver.revive()
        #expect(driver.state == .rested)
        #expect(driver.pickedAt[berries.id] != nil)
    }
}
