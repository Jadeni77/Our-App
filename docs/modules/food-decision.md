# Module: Food Decision — "What Should We Eat"

> Module #1. See platform doc `DESIGN.md` for the shared principles, core, and module contract this module plugs into. This file owns everything *specific* to deciding what to eat.

## Purpose
When we go out, we can never decide what to eat. This module helps us agree on a **cuisine/flavor** together in ~30 seconds, then recommends **nearby restaurants** of that type — in whichever of our languages the phone speaks, wherever we are.

---

## Module Decision Log (food-specific forks)
Cross-cutting decisions (iOS-native, module-first, localization, theme) live in the platform log. These are the food-specific forks worth not reopening.

| # | Decision | Rationale | Rejected alternative |
|---|----------|-----------|----------------------|
| F1 | Decide *cuisine/flavor type* first, not a specific restaurant | The real agony is "what type"; once that's settled, picking a place is easy — and it avoids needing a restaurant API for the decision itself | Swiping/abandoning on specific restaurants up front |
| F2 | Both must agree via an Agree / Re-roll loop | Matches how we actually decide ("say one, if we both like it we go"); keeps it to ~30s | Card-swipe matching, scoring systems |
| F3 | Restaurant lookup via Apple MapKit `MKLocalSearch` | Free, native, no API key, no billing; enough for "5 places near us, tap for directions" | Google Places — paid SKUs; photos billed per fetch; field mask escalates the tier |
| F4 | Silently record each decision from day one | Cheap now; becomes fuel for smarter picks and grows naturally into a history page | Building a history UI up front |
| F5 | Defer Google Places / photos / ratings | Decoration for our use case; free-but-plain beats paid-but-pretty until we genuinely miss it | Rich photo/rating cards in v1 |
| F6 | Cuisine pool becomes **localized data**: stable `id` + localized display names (en / zh-Hans / zh-Hant) + emoji; all module strings via the String Catalog (per platform P5) | We think about food in both languages — "火锅" *is* the cuisine, not a translation of it; and history must survive language switches (record the `id`, not the display string) | Keeping the English string pool and translating only the UI chrome (cuisine names are the heart of this module — half-localized is not localized) |
| F7 | Each cuisine carries **`searchTerms`** (multi-language variants, e.g. hotpot → 火锅 / hotpot / 麻辣火锅) and the provider picks/query-orders terms by **user region**, all behind the existing `RestaurantProvider` | The display name alone under-queries: "火锅" must find places in Chinese-speaking regions where POIs are tagged in Chinese, *and* the same cuisine must still return results where POIs are tagged in English | Using the localized display name as the raw `MKLocalSearch` query (breaks whenever display language ≠ the language local POIs are tagged in) |

*(Feature details that weren't real forks — random-pick vs manual entry, list vs map rendering — live in Scope below, not here.)*

---

## v1 Scope — ✅ built 2026-07-28, in real-use trial

### Core loop (~30s)
1. **Propose a cuisine** — two ways, both available: tap for a random draw from a built-in pool, **or** type one manually.
2. **Show the proposal big** on its own screen; hand the phone over.
3. **Other person decides:** **Agree ✅** (→ decided) or **Re-roll 🔄** (→ new proposal).
4. **Decided screen** celebrates the choice, then offers **"Find places near us."**
5. **Results:** `MKLocalSearch` on the cuisine → a **styled card list (not a map view)**: name, distance, **Directions** action (opens Apple Maps). Address/phone when available.

### Built-in cuisine pool
~30–40 hardcoded entries in one editable place (hotpot, ramen, Sichuan, sushi, burgers, Thai, pizza, tacos, Korean BBQ, pho, …). *(Superseded in v2 by F6's localized data pool.)*

### Silent history
On every completed decision (Agree), persist `{ date, cuisineChosen }` via the core's local persistence. **No UI in v1.** Seeds smarter future picks and the future history page.

### Data & rendering specifics
- **Source:** MapKit `MKLocalSearch`, cuisine string as the query, scoped to the user's current region. Hidden behind a `RestaurantProvider` protocol (per the module contract) so the source is swappable later.
- **Persistence:** SwiftData (or a thin local store).
- **Rendering:** SwiftUI card list; no `MKMapView` required.

---

## v2 Scope — localization + Chinese-capable search (next milestone)

### Localized module (F6, platform P5)
- Every user-facing string in the module (buttons, prompts, fail-soft copy, tile name) lives in the String Catalog: **en / zh-Hans / zh-Hant**.
- **Cuisine pool → localized data.** Each entry: stable `id`, display name per language, emoji, `searchTerms` (F7). One editable place, as before.
- **History survives language switches:** `DecisionRecord` gains the stable cuisine `id` alongside the chosen display string (typed-in cuisines keep string-only records). Existing v1 records stay valid — additive SwiftData migration only.
- Manual entry accepts input in any of the three languages; if it matches a pool entry's display name or search term in *any* language, it resolves to that entry (keeping emoji + searchTerms), else it's kept as a free-form string, exactly like v1.

### Chinese-capable restaurant search (F7)
- `RestaurantProvider` contract unchanged from the UI's point of view — the strategy is internal to the MapKit implementation.
- Query strategy: order the cuisine's `searchTerms` by user region/locale fit (e.g. zh-Hans-tagged regions try 火锅 first), query in order, **merge + dedupe** results until the existing cap (8); fall back through remaining terms when a term returns nothing. Fixed ~5 km region and fail-soft states carry over from v1 unchanged.
- Typed free-form cuisines search with the typed string, as today.

### Platform integration (per the updated module contract)
- Provide **tile metadata** (localized name + emoji) for the shell's launcher; the module opens from tile #1.
- Adopt the **core theme** (gradients, glass, springs, haptics) in all module screens — replacing v1's plain styling; behavior unchanged.

---

## Build Order

**v1 — ✅ complete (2026-07-28):**
1. ~~Cuisine pool + random pick + manual entry → propose screen.~~
2. ~~Agree / Re-roll decide screen + decided screen.~~
3. ~~Silent SwiftData persistence of completed decisions.~~
4. ~~`RestaurantProvider` protocol + MapKit implementation.~~
5. ~~Styled result card list + Directions; fail-soft states.~~
6. ~~Shared bits (persistence, shell) in platform core; module cleanly separated.~~

**v2 — current milestone:**
7. ~~Localized cuisine data model (`id` + per-language names + `searchTerms` + emoji) replacing the string pool; `DecisionRecord` gains cuisine `id` (additive migration).~~ ✅ (2026-07-29)
8. ~~String Catalog: every module string in en / zh-Hans / zh-Hant; manual entry resolves across languages.~~ ✅ (2026-07-29)
9. ~~Region-aware multi-term search inside the MapKit provider (query order, merge/dedupe, fallback); protocol surface unchanged.~~ ✅ (2026-07-29)
10. ~~Launcher tile metadata~~ ✅ shipped with the platform-shell milestone (2026-07-28). ~~Theme adoption~~ ✅ (2026-07-29)

## Definition of done (v1) — ✅ met 2026-07-28
On one phone: get a cuisine (random or typed) → agree/re-roll → land on a decision → see real nearby restaurants with directions, and each decision is silently recorded. **Then use it for real for a week before adding anything.**

## Definition of done (v2)
With the device set to each of en / zh-Hans / zh-Hant in turn: the full ritual reads natively (zero English leaking into Chinese runs and vice versa); rolling 火锅 in a Chinese-speaking region returns hotpot places; the same cuisine still returns results where POIs are tagged in English; history keeps recording (with cuisine `id`) across language switches; module screens wear the platform theme and launch from the shell tile.

*(Met in build — pending the human's tri-language on-device pass.)*

## Out of scope for v2
Two-phone sync / backend · accounts / pairing · Google Places / photos / ratings · history UI (persist data only) · widgets · notifications · languages beyond en / zh-Hans / zh-Hant.

## Module open questions
- ~~Bias the random pick by history from the start, or stay purely random until the history module lands?~~ **Resolved for v1 (2026-07-28): purely random.** History is recorded from day one, so nothing is lost; bias arrives with the history module.
- ~~`MKLocalSearch` region/radius — fixed, or adapt to how spread out results are?~~ **Resolved for v1 (2026-07-28): fixed ~5 km region, capped at 8 results.** Revisit if real use shows sparse/dense areas need adaptation.
- ~~Multi-term search (F7): query terms sequentially with early exit once the cap is filled, or fan out in parallel and merge?~~ **Resolved for v2 (2026-07-29): sequential with early exit at the cap.**
- ~~Region fit for term ordering: derive from the search region's locale, the device locale, or both?~~ **Resolved for v2 (2026-07-29): reverse-geocoded search location first, device region fallback.**
