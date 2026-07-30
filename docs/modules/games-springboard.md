# Module doc: Games Springboard — the launcher surface

> Shell v3's Games tab (platform P11). *Architecturally this is core shell chrome — the launcher that mounts modules (per P4, the frame around modules can't be their sibling) — not a mountable module itself.* It still gets a module-style doc because it's feature-sized: everything springboard-specific lives here, keeping `DESIGN.md` §4 to one bullet. Session spec: `docs/superpowers/specs/2026-07-29-tab-shell-design.md`.

## Purpose

Launching a module should feel like an iPhone home screen that belongs to us: every module is an **app tile** on the **Games tab**; we arrange tiles and folder-style **collections** however we like, in a full **jiggle mode**; tapping a tile opens its module full-screen. The springboard is the platform's one generic launching mechanism — a new module shows up here with zero springboard changes.

---

## Module Decision Log (springboard-specific forks)

The platform log (P11) owns the big forks: tab bar over the rail, springboard concept, full jiggle mode, JSON-preference-document over SwiftData, per-device layout. These are the finer springboard forks.

| # | Decision | Rationale | Rejected alternative |
|---|----------|-----------|----------------------|
| S1 | **Custom drag engine**: one `DragGesture` driving a controller that hit-tests per-tile frames (anchor preferences); gap-vs-target decisions are pure functions | Native SwiftUI DnD gives no control over the lift preview, arm-on-hover timing, or dragging a member out of an open folder — the three things the iPhone feel hangs on | `draggable`/`dropDestination` (fine for lists, wrong shape for a springboard) |
| S2 | **Arm-on-hover, release-to-act**: hovering a drag over a target ~0.4 s arms it (scale + glow); releasing while armed forms/joins the collection | One rule covers both forming and adding; the delay prevents accidental grouping while dragging past tiles | Acting instantly on hover (accident-prone); iOS-style spring-load that *opens* the folder mid-drag (more machinery than two people need) |
| S3 | **One vertically scrolling grid**; horizontal paging deferred | The layout is a flat ordered list, so auto-flowing it into pages with dots later is mechanical — paging waits until the grid overflows | Building paging + page dots for a handful of tiles |
| S4 | **DEBUG-only sample tiles** (2–3 "coming soon" placeholders) | Collections need ≥2 tiles to exercise end-to-end while only one real module exists; RELEASE stays honest and shows only real modules | Shipping placeholder tiles; leaving jiggle untestable until module #2 |
| S5 | **Reconcile rules**: a registered module missing from the layout auto-appends to the root grid; stale ids are dropped; a collection emptied by either dissolves | Adding a module stays a one-line `AppShell` change; layout drift can never block launching (fail-soft, principle 7) | Strict layout validation (turns drift into dead ends) |
| S6 | **Collection names are user data** — stored verbatim, never translated; only the default "New collection" is localized | The names are *ours*, written in whichever language we felt like that day — the app has no business rewriting them | Localizing/translating stored names |

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
4-column `LazyVGrid`; app tile = rounded glass square (core `GlassStyle`), large emoji, localized name beneath. Collection tile = same square holding up to 9 member emojis in a 3×3 mini-grid, name beneath. Folder opens as a zoom overlay (matched geometry). Background: `DreamyBackground` without tilt parallax (motion sensors stay Home-only). Launching goes through the existing `ModuleHostView` full-screen cover — the tab bar hides during a ritual. `ModuleDescriptor` is unchanged.

### Jiggle mode (the behavioral contract)

| Interaction | Behavior |
|---|---|
| Enter | Long-press (~0.5 s) any tile → all tiles wobble (per-tile phase stagger); **Done** glass pill top-trailing; haptic |
| Reorder | Drag a tile; neighbors spring apart to open a gap; release commits |
| Form a collection | Drag over another tile → arm-on-hover (S2) → release while armed → collection of {target, dragged}; folder overlay opens with the name field focused |
| Add to collection | Drag over a collection tile → arm-on-hover → release → appended last |
| Open a collection | Tap (both modes) → overlay zooms open; normal mode: tap a member to launch; edit mode: opens in editing state |
| Edit inside a folder | Members wobble and reorder by drag; dragging a member outside the overlay returns it to the root grid; name is editable |
| Auto-dissolve | Removing the last member deletes the collection — empty folders can't exist |
| Exit | Done or tap empty background; haptic; every mutation already saved |
| Reduce Motion | Wobble replaced by a static edit affordance; drag behavior unchanged |

No app deletion (modules are code), no badges. VoiceOver: tiles and folders stay labeled and launchable; drag-arranging under VoiceOver is a logged gap.

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

## Module open questions

- Once sync lands: does the layout stay per-device (each of us arranges our own page) or become shared? Parked to the sync milestone.
- Grid metrics (4 columns, tile size) — revisit after real use on both phones.
