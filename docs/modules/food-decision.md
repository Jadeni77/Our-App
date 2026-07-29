# Module: Food Decision — "What Should We Eat"

> Module #1. See platform doc `DESIGN.md` for the shared principles, core, and module contract this module plugs into. This file owns everything *specific* to deciding what to eat.

## Purpose
When we go out, we can never decide what to eat. This module helps us agree on a **cuisine/flavor** together in ~30 seconds, then recommends **nearby restaurants** of that type.

---

## Module Decision Log (food-specific forks)
Cross-cutting decisions (iOS-native, module-first) live in the platform log. These are the food-specific forks worth not reopening.

| # | Decision | Rationale | Rejected alternative |
|---|----------|-----------|----------------------|
| F1 | Decide *cuisine/flavor type* first, not a specific restaurant | The real agony is "what type"; once that's settled, picking a place is easy — and it avoids needing a restaurant API for the decision itself | Swiping/abandoning on specific restaurants up front |
| F2 | Both must agree via an Agree / Re-roll loop | Matches how we actually decide ("say one, if we both like it we go"); keeps it to ~30s | Card-swipe matching, scoring systems |
| F3 | Restaurant lookup via Apple MapKit `MKLocalSearch` | Free, native, no API key, no billing; enough for "5 places near us, tap for directions" | Google Places — paid SKUs; photos billed per fetch; field mask escalates the tier |
| F4 | Silently record each decision from day one | Cheap now; becomes fuel for smarter picks and grows naturally into a history page | Building a history UI up front |
| F5 | Defer Google Places / photos / ratings | Decoration for our use case; free-but-plain beats paid-but-pretty until we genuinely miss it | Rich photo/rating cards in v1 |

*(Feature details that weren't real forks — random-pick vs manual entry, list vs map rendering — live in Scope below, not here.)*

---

## v1 Scope

### Core loop (~30s)
1. **Propose a cuisine** — two ways, both available: tap for a random draw from a built-in pool, **or** type one manually.
2. **Show the proposal big** on its own screen; hand the phone over.
3. **Other person decides:** **Agree ✅** (→ decided) or **Re-roll 🔄** (→ new proposal).
4. **Decided screen** celebrates the choice, then offers **"Find places near us."**
5. **Results:** `MKLocalSearch` on the cuisine → a **styled card list (not a map view)**: name, distance, **Directions** action (opens Apple Maps). Address/phone when available.

### Built-in cuisine pool
~30–40 hardcoded entries in one editable place (hotpot, ramen, Sichuan, sushi, burgers, Thai, pizza, tacos, Korean BBQ, pho, …).

### Silent history
On every completed decision (Agree), persist `{ date, cuisineChosen }` via the core's local persistence. **No UI in v1.** Seeds smarter future picks and the future history page.

### Data & rendering specifics
- **Source:** MapKit `MKLocalSearch`, cuisine string as the query, scoped to the user's current region. Hidden behind a `RestaurantProvider` protocol (per the module contract) so the source is swappable later.
- **Persistence:** SwiftData (or a thin local store).
- **Rendering:** SwiftUI card list; no `MKMapView` required.

---

## Build Order (current milestone)
1. Cuisine pool + random pick + manual entry → propose screen. Pure `@State`, no persistence. Get the loop running first.
2. Agree / Re-roll decide screen + decided screen. Play with the feel.
3. Silent SwiftData persistence of completed decisions.
4. `RestaurantProvider` protocol + MapKit implementation, wired to the decided screen.
5. Styled result card list + Directions; handle permission-denied / no-results / empty states.
6. Refactor genuinely shared bits (persistence, shell) into the platform core; keep the module cleanly separated.

## Definition of done (v1)
On one phone: get a cuisine (random or typed) → agree/re-roll → land on a decision → see real nearby restaurants with directions, and each decision is silently recorded. **Then use it for real for a week before adding anything.**

## Out of scope for v1
Two-phone sync / backend · accounts / pairing · Google Places / photos / ratings · history or home-page UI (persist data only) · widgets · notifications.

## Module open questions
- ~~Bias the random pick by history from the start, or stay purely random until the history module lands?~~ **Resolved for v1 (2026-07-28): purely random.** History is recorded from day one, so nothing is lost; bias arrives with the history module.
- ~~`MKLocalSearch` region/radius — fixed, or adapt to how spread out results are?~~ **Resolved for v1 (2026-07-28): fixed ~5 km region, capped at 8 results.** Revisit if real use shows sparse/dense areas need adaptation.
