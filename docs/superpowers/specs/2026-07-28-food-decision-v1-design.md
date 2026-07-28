# Food Decision v1 — Session Design Spec (2026-07-28)

> Thin spec: `docs/DESIGN.md` and `docs/modules/food-decision.md` remain the source of
> truth for vision, principles, decision logs, and scope. This spec records only what
> those docs leave open, as resolved and approved this session. Scope: **full v1**
> (build order steps 1–6, definition of done).

## Approved decisions (this session)

1. **Scaffolding** — hand-written minimal `OurApp.xcodeproj` using Xcode 16+
   synchronized folder groups (`PBXFileSystemSynchronizedRootGroup`). The project
   points at source folders; new files are picked up automatically with no per-file
   project edits and no extra tooling. $0, no dependencies.
2. **App name** — `OurApp` (placeholder; display name trivially changeable later).
3. **Open question: random bias** — purely random draws in v1; no history bias until
   the history module lands. History is recorded from day one regardless.
4. **Open question: search region** — fixed region, ~5 km span centered on the user,
   results capped at 8. Adaptive radius deferred until real use demands it.

## Project structure

```
Our-App/
├── OurApp.xcodeproj                 hand-written, synchronized folder groups
├── OurApp/
│   ├── App/
│   │   ├── OurAppApp.swift          @main — builds ModelContainer, mounts shell
│   │   └── AppShell.swift           where modules mount; today just FoodDecision
│   ├── Core/
│   │   └── Persistence.swift        shared ModelContainer factory
│   └── Modules/FoodDecision/
│       ├── FoodDecisionModule.swift        module entry point view
│       ├── CuisinePool.swift               ~35 hardcoded entries, one editable place
│       ├── DecisionRecord.swift            @Model { date, cuisineChosen }
│       ├── FoodDecisionFlow.swift          @Observable state machine (pure logic)
│       ├── RestaurantProvider.swift        protocol + Restaurant value type
│       ├── MapKitRestaurantProvider.swift  MKLocalSearch + CoreLocation impl
│       └── Views/
│           ├── ProposeView.swift           random draw + manual entry
│           ├── DecideView.swift            proposal shown big; Agree / Re-roll
│           ├── DecidedView.swift           celebration → "Find places near us"
│           ├── RestaurantListView.swift    card list + empty/denied/error states
│           └── RestaurantCard.swift        name, distance, address/phone, Directions
└── OurAppTests/                     unit tests (Swift Testing)
```

Seams per the module contract: the module never touches another module; the shell
injects core persistence (SwiftData `ModelContainer`); MapKit hides behind
`RestaurantProvider` (decision F3).

## State flow

`FoodDecisionFlow` (`@Observable`) owns a phase enum:

```
propose ──(random draw / manual entry)──▶ deciding(cuisine)
deciding ──agree()──▶ decided(cuisine)     [persists DecisionRecord, silent — F4]
deciding ──reroll()──▶ deciding(new random cuisine)
decided ──startOver()──▶ propose
```

Views are thin renderings of the phase. All transitions unit-testable without UI.

## Restaurant search

- `protocol RestaurantProvider { func search(cuisine: String) async throws -> [Restaurant] }`
- `Restaurant`: value type — name, distance from user, optional address/phone, and a
  handle for opening directions.
- MapKit implementation: when-in-use location → `MKLocalSearch` with the cuisine as
  natural-language query, POI filter restaurants, fixed ~5 km region, cap 8 results,
  sorted by distance. Directions via `MKMapItem.openInMaps`.

## Fail-soft states (principle 7)

| Situation | Behavior |
|---|---|
| Location permission denied | Friendly card + "Open Settings" button |
| No results | "Nothing nearby for X — try another cuisine" + back action |
| Search error | Message + Retry button |

## Testing

- **TDD (logic layer, Swift Testing):** flow transitions; `agree()` persists a
  `DecisionRecord` (in-memory `ModelContainer`); pool draw behavior; result handling
  via a mock `RestaurantProvider`.
- **Views:** verified by building and running on the iPhone 17 Pro simulator
  (MapKit/CoreLocation behavior is exercised live, not unit-mocked beyond the
  provider seam).

## Housekeeping

- Git repo initialized this session.
- Per working agreement §8, append this session's decisions: platform log row for
  the hand-written-pbxproj choice; module doc open questions annotated with their
  v1 resolutions.
