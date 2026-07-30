# Tab Shell (Shell v3) — Session Design Spec (2026-07-29)

> Thin spec: `docs/DESIGN.md` remains the source of truth for vision, principles, and
> decision logs (this session adds P11 and the §7 sync direction there). This spec
> records only what those docs leave open, as resolved and approved this session.
> Scope: **the tab shell milestone only** — two-phone sync is explicitly deferred;
> its chosen direction lives in DESIGN.md §7, not here.

## Approved decisions (this session)

1. **Shell becomes a bottom tab bar** (P11, supersedes P8's launcher rail — the home
   layout itself is untouched): a native `TabView` with two surfaces, **Home** (the
   couples hero, minus the rail) and **Games**. Every future surface (Us, memories…)
   is one new `Tab` entry. Labels localized en / zh-Hans / zh-Hant.
2. **Games tab is a springboard**: one vertically-scrolling grid whose items are
   **app tiles** (one per module) and **collections** (iOS-folder style: rounded
   square with a mini-grid preview of members, name beneath). Loose tiles and
   collections mix freely. Food Decision is app #1.
3. **Arranging is full jiggle mode** — the owners' explicit call: *real iPhone feel*,
   built now, not deferred. Long-press to wobble, drag to reorder, drag-onto-tile to
   form collections. Detailed interaction spec below.
4. **Layout is a per-device preference document** — a small versioned Codable JSON
   file, *not* SwiftData (it's a preference, not records). Each partner arranges
   their own Games page; whether layout syncs is a question for the sync milestone.
5. **Horizontal paging deferred**: the layout is a flat ordered list, so flowing it
   into iPhone-style pages with dots later is mechanical. Paging waits until the
   grid actually overflows.
6. **DEBUG-only sample tiles**: with a single real module, collection-forming can't
   be exercised. DEBUG builds register 2–3 placeholder descriptors (emoji + name,
   entry view = a friendly "coming soon" card) so jiggle/collections are testable
   end-to-end. RELEASE shows only real modules.

## Project structure (new / changed)

```
OurApp/
├── App/
│   └── AppShell.swift                   TabView (Home | Games); per-surface module lists
├── Core/Shell/
│   ├── CouplesHomeView.swift            hero unchanged; launcher rail removed
│   ├── ModuleLauncherRail.swift         DELETED (P11) — with its -openDrawer DEBUG arg
│   └── GamesTab/
│       ├── GamesLayout.swift            Codable document: version + ordered items
│       ├── GamesLayoutStore.swift       @Observable; JSON load/save; reconcile; mutations
│       ├── GamesTabView.swift           background + LazyVGrid of items
│       ├── AppTileView.swift            glass square, emoji, localized name beneath
│       ├── CollectionTileView.swift     3×3 mini-grid of member emojis, name beneath
│       ├── FolderOverlayView.swift      zoom-open collection panel (matched geometry)
│       └── JiggleController.swift       edit-mode state + drag engine (pure logic core)
```

`ModuleDescriptor` and `ModuleHostView` are **unchanged** — the layout references
module `id`s from the outside; launching stays the existing full-screen cover
(tab bar hides during a ritual).

## Layout model

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
        var name: String               // user data — stored verbatim, never translated
        var members: [String]          // ordered module ids
    }
}
```

- Persisted as one JSON file in Application Support, written atomically on every
  mutation (not only on edit-mode exit).
- **Reconcile on load / registration** (the extensibility rules): a registered
  module absent from the layout auto-appends to the end of the root grid — so adding
  module #2 stays a one-line `AppShell` change; a layout entry whose module no longer
  exists is silently dropped (collections keep surviving members); a collection
  emptied by reconcile or editing dissolves.
- Corrupt/unreadable file → silently rebuild the default layout (all modules loose,
  registration order). Fail-soft, principle 7.
- New collections get a localized default name ("New collection"); the name is user
  data from then on.

## Jiggle mode — interaction spec

| Interaction | Behavior |
|---|---|
| Enter | Long-press (~0.5 s) any tile → all tiles wobble (small rotation oscillation, per-tile phase stagger); a **Done** glass pill appears top-trailing; haptic tap |
| Reorder | Drag a tile; neighbors spring apart to open a gap; release commits order |
| Form a collection | Drag a tile over another tile → after ~0.4 s of hover the target **arms** (scale + glow — the delay prevents accidental grouping while dragging past); release while armed → collection of {target, dragged} created, folder overlay opens with the name field focused for immediate rename |
| Add to collection | Drag a tile over a collection tile → same arm-on-hover; release while armed → appended as last member |
| Open a collection | Tap (both modes) → folder overlay zooms open via matched geometry; in normal mode tapping a member launches its module; in edit mode the folder opens in its editing state |
| Edit inside a folder | In edit mode members wobble and reorder by drag; dragging a member **outside the overlay** moves it back to the root grid; the name is an editable text field |
| Auto-dissolve | Removing the last member deletes the collection — empty folders can't exist |
| Exit | Done button or tap on empty background; haptic |
| Reduce Motion | Wobble replaced by a static edit affordance (subtle tile border); all drag behavior unchanged |

No app deletion (modules are code), no badges. VoiceOver: tiles/folders stay fully
labeled and launchable; *drag-arranging* under VoiceOver is a known gap for now
(personal two-user app; logged in Out of scope).

**Implementation approach** (flagged per working agreement — the non-obvious bit):
a custom drag engine, not native `draggable`/`dropDestination` — native DnD gives no
control over lift preview, arm-on-hover timing, or drag-out-of-overlay. One
`DragGesture` drives a `JiggleController` that hit-tests against per-tile frames
captured via anchor preferences; gap-vs-target decisions are pure functions over
those frames (unit-testable without UI). Wobble is a repeating `rotationEffect`
with random per-tile phase, paused for the tile being dragged. This is the fiddly
part of the milestone — expect iteration on device before it feels right.

## Rendering & chrome

- Grid: 4 columns, `LazyVGrid`; app tile = rounded glass square (core `GlassStyle`),
  large centered emoji, caption beneath — visually continuous with today's rail tiles.
- Collection tile: same square containing up to 9 member emojis in a 3×3 mini-grid.
- Games background: `DreamyBackground` without tilt parallax (motion sensors stay a
  Home-only consumer).
- Tab bar: **native** `TabView` on the Xcode 26 toolchain — the system bar (Liquid
  Glass) themed with core tint; no hand-rolled bar. SF Symbols + localized labels
  (Home / Games).
- Home: unchanged except the rail is gone and the hero owns the full canvas; the
  gear button stays bottom-leading. DEBUG launch args for headless screenshots:
  `-openDrawer` retires with the rail; `-selectGames` and `-jiggleMode` arrive
  (existing `-openSettings` pattern).

## Testing

- **TDD (Swift Testing), logic layer:** `GamesLayoutStore` — reconcile rules
  (auto-append new module, drop stale id, dissolve emptied collection, order
  preserved), mutations (reorder, group, add-to/remove-from collection, rename,
  auto-dissolve), JSON round-trip, corrupt-file recovery. `JiggleController` —
  mode transitions and hit-test/gap decisions as pure functions over synthetic
  frames.
- **Views:** simulator build + headless screenshot pass via the launch args (grid,
  folder open, jiggle mode) in all three languages; gesture *feel* (drag, spring-load,
  wobble) is verified by hand on device — it can't be meaningfully unit-tested.

## Out of scope

Two-phone sync (direction recorded in DESIGN.md §7) · horizontal paging/page dots ·
Home quick-action row · an Us tab · badges · VoiceOver drag-arranging ·
widgets/notifications.

## Definition of done

In each of en / zh-Hans / zh-Hant, on simulator (and a device pass for feel): the
app opens to Home with the hero unchanged and no rail; the Games tab shows the Food
Decision tile (plus DEBUG samples); long-press wobbles; drag reorders; drag-onto-tile
forms a collection that renames, opens, launches, and survives relaunch; a member
dragged out of its folder returns to the grid and the last removal dissolves the
folder; every string is localized; the full test suite is green.

## Housekeeping

- DESIGN.md updated this session: §4 launcher bullet rewritten for the springboard,
  §5 gains P11, §7 records the sync direction (CloudKit `CKShare` + `CKSyncEngine`
  recommended; parcs WebSocket+SQLite as $0 fallback; Firebase rejected; record-
  hygiene rule for future synced models).
- Branch `tab-shell` from `develop`; squash-PR back into `develop` (P10).
- `ModuleLauncherRail.swift` is deleted at implementation time, not in the spec commit.
