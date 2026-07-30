# Module doc: Games Springboard — the launcher surface

> Shell v3's Games tab (platform P11). *Architecturally this is core shell chrome — the launcher that mounts modules (per P4, the frame around modules can't be their sibling) — not a mountable module itself.* It still gets a module-style doc because it's feature-sized: everything springboard-specific lives here, keeping `DESIGN.md` §4 to one bullet. Session spec: `docs/superpowers/specs/2026-07-29-tab-shell-design.md`.

## Purpose

Launching a module should feel like an iPhone home screen that belongs to us: every module is an **app tile** on the **Games tab**; we arrange tiles and folder-style **collections** however we like, in a full **jiggle mode**; tapping a tile opens its module full-screen. The springboard is the platform's one generic launching mechanism — a new module shows up here with zero springboard changes. From v2 it is also **our second home screen for the games we actually play** (S7): tiles for real apps installed on the phone — same game, launched from our springboard instead of the system one.

---

## Module Decision Log (springboard-specific forks)

The platform log (P11) owns the big forks: tab bar over the rail, springboard concept, full jiggle mode, JSON-preference-document over SwiftData, per-device layout. These are the finer springboard forks.

| # | Decision | Rationale | Rejected alternative |
|---|----------|-----------|----------------------|
| S1 | **Custom drag engine**: one `DragGesture` driving a controller that hit-tests per-tile frames (`.onGeometryChange`); gap-vs-target decisions are pure functions | Native SwiftUI DnD gives no control over the lift preview, arm-on-hover timing, or dragging a member out of an open folder — the three things the iPhone feel hangs on | `draggable`/`dropDestination` (fine for lists, wrong shape for a springboard) |
| S2 | **Arm-on-hover, release-to-act**: hovering a drag over a target ~0.4 s arms it (scale + glow); releasing while armed forms/joins the collection | One rule covers both forming and adding; the delay prevents accidental grouping while dragging past tiles | Acting instantly on hover (accident-prone); iOS-style spring-load that *opens* the folder mid-drag (more machinery than two people need) |
| S3 | **One vertically scrolling grid**; horizontal paging deferred | The layout is a flat ordered list, so auto-flowing it into pages with dots later is mechanical — paging waits until the grid overflows | Building paging + page dots for a handful of tiles |
| S4 | **DEBUG-only sample tiles** (2–3 "coming soon" placeholders) | Collections need ≥2 tiles to exercise end-to-end while only one real module exists; RELEASE stays honest and shows only real modules | Shipping placeholder tiles; leaving jiggle untestable until module #2 |
| S5 | **Reconcile rules**: a registered module missing from the layout auto-appends to the root grid; stale ids are dropped; a collection emptied by either dissolves | Adding a module stays a one-line `AppShell` change; layout drift can never block launching (fail-soft, principle 7) | Strict layout validation (turns drift into dead ends) |
| S6 | **Collection names are user data** — stored verbatim, never translated; only the default "New collection" is localized | The names are *ours*, written in whichever language we felt like that day — the app has no business rewriting them | Localizing/translating stored names |
| S7 | **External app tiles** (v2): the springboard also launches real apps installed on the phone — added manually, launched via URL scheme with App Store fallback, official artwork via the iTunes Search API | The Games tab should hold the games we *actually play* (e.g. Identity V) — a launcher with one module tile is a stub next to our real library, and launching from *our* space is the whole point | Module-tiles-only purity (v1's premise — still true for modules, extended for games); embedding another app's UI (impossible on iOS); auto-detecting installed apps (no iOS API — privacy) |

---

## v1 Scope — ✅ built 2026-07-30, pending the human's on-device feel pass

### Tab frame (platform §4)
Native `TabView` on the Xcode 26 toolchain (system Liquid Glass bar, core tint — no hand-rolled bar): **Home** (the couples hero, rail removed, gear stays) | **Games** (this springboard). Labels localized en / zh-Hans / zh-Hant. Every future surface is one new `Tab`.

### Layout model
```swift
struct GamesLayout: Codable {          // version: 1
    var version: Int
    var items: [Item]                  // ordered, root grid
    enum Item: Codable {
        case app(moduleID: String)
        case collection(Collection)
    }
    struct Collection: Codable {
        var id: UUID
        var name: String               // user data (S6)
        var members: [String]          // ordered module ids
    }
}
```
One JSON file in Application Support, written atomically on every mutation; per device (P11). Corrupt/unreadable → silently rebuild the default (all modules loose, registration order). Reconcile per S5 on load and registration.

### Rendering
4-column `LazyVGrid`; app tile = rounded glass square (core `GlassStyle`), large emoji, localized name beneath. Collection tile = same square holding up to 9 member emojis in a 3×3 mini-grid, name beneath. Folder opens as a zoom overlay (matched geometry) titled by the collection's name **above** its grid, like an open iOS folder. Background: `DreamyBackground` without tilt parallax (motion sensors stay Home-only). Launching goes through the existing `ModuleHostView` full-screen cover — the tab bar hides during a ritual. `ModuleDescriptor` is unchanged.

### Jiggle mode (the behavioral contract)

| Interaction | Behavior |
|---|---|
| Enter | Long-press (~0.5 s) any tile — in the root grid or inside an open folder → all tiles wobble (per-tile phase stagger); **Done** glass pill top-trailing; haptic |
| Reorder | Drag a tile; neighbors spring apart to open a gap; release commits |
| Form a collection | Drag over another tile → arm-on-hover (S2) → release while armed → collection of {target, dragged}; folder overlay opens with the name field focused |
| Add to collection | Drag over a collection tile → arm-on-hover → release → appended last |
| Open a collection | Tap (both modes) → overlay zooms open; normal mode: tap a member to launch; edit mode: opens in editing state |
| Edit inside a folder | Members wobble and reorder by drag; dragging a member outside the overlay returns it to the root grid; name is editable — long-pressing a member enters edit mode from here (deliberately *without* focusing the name, unlike just-formed collections) |
| Auto-dissolve | Removing the last member deletes the collection — empty folders can't exist |
| Exit | Done or tap empty background; haptic; every mutation already saved |
| Reduce Motion | Wobble replaced by a static edit affordance; drag behavior unchanged |
| Add a game (v2) | A **+** glass pill top-leading (opposite Done) opens the S7 add sheet |
| Delete (v2, externals only) | In edit mode external tiles wear an ⓧ badge (root grid only — drag a foldered external out first) → confirm → registry entry, root tile, collection references, and cached artwork all go (S5 dissolve applies); module tiles never delete |

No module deletion (modules are code), no badges beyond the external ⓧ. VoiceOver: tiles and folders stay labeled and launchable; drag-arranging under VoiceOver is a logged gap.

### DEBUG support
Launch args for headless screenshot verification: `-selectGames`, `-jiggleMode` (the rail's `-openDrawer` retires with it). Sample tiles per S4.

---

## Build Order

1. `GamesLayout` + `GamesLayoutStore` with reconcile rules and persistence — TDD, logic only.
2. Tab frame (Home | Games), grid rendering, launch-from-tile; rail deleted.
3. Folder overlay (open, launch from inside, rename).
4. Jiggle engine: enter/exit + wobble → drag-reorder → arm-on-hover form/add → drag-out-of-folder.
5. Polish: haptics, Reduce Motion path, localization sweep, screenshot args.

## Definition of done (v1)

In each of en / zh-Hans / zh-Hant, on simulator (and a device pass for feel): the app opens to Home with the hero unchanged and no rail; Games shows the Food Decision tile (plus DEBUG samples); long-press wobbles; drag reorders; drag-onto-tile forms a collection that renames, opens, launches, and survives relaunch; a member dragged out returns to the grid and the last removal dissolves the folder; every string is localized; the full suite is green.

## Out of scope for v1

Two-phone sync (direction in `DESIGN.md` §7 — note the layout is a per-device preference and may never sync) · horizontal paging / page dots · Home quick-action row · an Us tab · badges · VoiceOver drag-arranging · widgets / notifications.

## v2 Scope — external app tiles (S7) — ✅ built 2026-07-30, pending the human's on-device pass

The games we actually play get tiles on **our** springboard; tapping launches the real app — the OS switches to the game full-screen, exactly like tapping it on the system home screen, and you return via the app switcher (not our Close button). iOS can't embed another app's UI or list what's installed, so tiles are added manually and launch via URL scheme with fail-soft fallbacks.

### Layout model (`GamesLayout` version 1 → 2)

New item case alongside `app` and `collection`, backed by a top-level registry:

```swift
case external(externalID: UUID)     // references the registry below

// GamesLayout gains: var externalApps: [ExternalApp]
struct ExternalApp: Codable {
    var id: UUID
    var name: String        // user data — S6 applies, never translated
    var emoji: String       // fallback glyph, default 🎮
    var artworkURL: URL?    // official icon via iTunes Search API, cached; emoji when absent
    var launchURL: URL?     // the app's custom URL scheme, e.g. identityv://…
    var storeURL: URL?      // App Store page fallback
}
```

Externals live in the registry and are referenced by id — `Collection.members` stays `[String]` (external members are UUID strings), which is what lets version-1 documents decode losslessly *and* externals join collections. Reconcile (S5) treats the registry as the source of truth: dangling references drop, a registry entry that lost its tile is re-materialized at the end of the grid, and **external tiles are never auto-dropped** — they aren't registered modules, so only the user removes them: jiggle mode gains a delete affordance *for external tiles only* (modules still can't be deleted).

### Add flow

In jiggle mode, a **"+" glass pill** (top-leading, opposite Done) opens a sheet:
- a small **curated catalog** (names only for now — schemes get pinned with Test launch; the starter list is an open question below), and
- **manual entry** (name + optional scheme) with a **"Test launch"** button that proves a scheme on the spot — this is how we pin down undocumented schemes like Identity V's on a real phone.
Artwork + store link come from the **iTunes Search API** by name (free, keyless), cached to Application Support; every fetch fails soft to the emoji.

### Launch behavior (principle 7 — never a dead end)

`UIApplication.open(launchURL)` → on failure open `storeURL` → neither works: friendly "can't open" message with an edit affordance. No `LSApplicationQueriesSchemes` declarations needed — we never call `canOpenURL`; `open()`'s completion is the probe.

### Everything else is unchanged

External tiles reorder, join collections (their emoji/artwork counts in the 3×3 mini-grid), and persist exactly like app tiles. Add-flow UI strings localized en / zh-Hans / zh-Hant; tile names stay user data.

---

## Build Order (v2)

6. `ExternalApp` + layout v2 decode/migration + reconcile guarantees (never-auto-drop, delete-external-only) — TDD, logic only.
7. Add-flow sheet (catalog + manual entry + test launch) with iTunes artwork fetch and cache — fail-soft throughout.
8. Launch path with scheme → store → message fallbacks; delete affordance in jiggle; localization sweep.

## Definition of done (v2)

On a real phone: add Identity V through the add flow; its tile (official artwork, or emoji fallback) sits among modules and collections, survives reorder, foldering, and relaunch; tapping switches to the actual game; a tile with a broken scheme falls back to its App Store page; deleting an external tile works in jiggle and modules still can't be deleted; all new strings read natively in en / zh-Hans / zh-Hant; full suite green.

## Module open questions

- v3 candidate — **share-sheet import** (owners' "pick the app" idea, 2026-07-30, in the only shape iOS allows): a Share extension that accepts App Store links — find the game in the App Store, Share → OurApp, and the tile arrives with the exact name/artwork/store id, zero typing. Needs a new extension target + an App Group to reach the layout document; milestone-sized.
- v3 candidate — **in-app App Store panel** (`SKStoreProductViewController`): schemeless tiles present the store page *inside* OurApp (Get/Open without leaving), the closest iOS permits to "download it from inside our app" — installing apps is reserved to the App Store by the sandbox, so true in-app installs/embedded games are impossible, not just hard.

- Once sync lands: does the layout stay per-device (each of us arranges our own page) or become shared? Parked to the sync milestone.
- Grid metrics (4 columns, tile size) — revisit after real use on both phones.
- v2: curated catalog contents — which games do we two want pre-listed? (Owners' list; Identity V is #1.)
- v2: the Shortcuts bridge (`shortcuts://run-shortcut?name=X` + an "Open App" action) launches *any* app when no URL scheme works, at the cost of one-time setup per game and a visible bounce through Shortcuts. **Usable today** — the link field accepts `shortcuts://` URLs (spaces get percent-encoded) — its trigger fired 2026-07-30 when no guessed scheme opened Identity V. Remaining idea: first-class UI (a "use a Shortcut instead" helper in the add sheet).
- v2 follow-up: **detecting installed games** — iOS never lists installed apps (privacy), so full auto-detection is impossible; but a curated catalog *with known schemes* could probe via `canOpenURL` (requires declaring each scheme in `LSApplicationQueriesSchemes`, ≤50) and offer one-tap "add Identity V?" suggestions. Same data gap as launching: someone has to collect real schemes. Revisit once we've pinned schemes for the games we actually play (owners asked 2026-07-30; would soften S7's rejected-alternative note from "impossible" to "possible for a curated list").
