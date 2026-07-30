# DESIGN.md — Platform (extensible two-person iOS app)

> **Source of truth for the whole app.** This is the *platform* doc — it holds only what's true across every module. Per-module detail lives in `docs/modules/`. Read this at the start of every session, then read the doc for whatever module you're working on.
>
> **How this doc stays small:** anything specific to one feature goes in that module's doc, not here. Adding a new feature = a new file in `docs/modules/` + a new row in the Module Index (§6). This doc should barely change once a module exists.
>
> Prompts are work orders derived from these docs, e.g. *"Build milestone-1 slice per docs/modules/food-decision.md."*

---

## 1. Vision

A small, native iOS app my partner and I use daily — **not** a big app, but a growing set of tiny, high-quality **modules** sharing a thin common **core**. The platform grows *out of* building real modules; we never build framework ahead of a feature that needs it.

The app opens into **our space** — a themed couples home that feels like it belongs to the two of us — and modules launch from there. Module #1 (v1 built) helps us decide what to eat. Future modules are listed in §6.

---

## 2. Goals & Non-Goals (platform level)

**Goals:** be something we actually open daily; keep a clean foundation so new modules slot in without rewrites; stay free to build and run until we choose to ship.

**Non-Goals:** not a big app (depth over breadth); not social / multi-couple / public; not cross-platform.

---

## 3. Design Principles (durable rules every decision is checked against)

1. **iOS-native first** — Swift/SwiftUI, native APIs, native feel. No cross-platform layer.
2. **Local-first until proven** — no backend / sync / accounts until a feature clearly needs it *and* daily use has justified the cost.
3. **Ultra-short interactions** — minimize taps; each module is a quick ritual, not a form. (The shell adds at most the launcher's lightweight open-and-tap to reach a module, and never taps inside a ritual.)
4. **Free until ship** — \$0 to build and test; pay only when earned (App Store / permanent install).
5. **Modules over a thin core** — features are self-contained, talk through narrow interfaces; the core stays small and holds only what's genuinely shared.
6. **Build the feature, grow the platform** — never scaffold platform ahead of a real module. Leave clean seams; don't build empty rooms.
7. **Fail soft** — permission denials and empty states degrade to friendly messages, never dead ends.
8. **Localized from the first line** — every user-facing string ships in **English, 简体中文 (zh-Hans), and 繁體中文 (zh-Hant)** via String Catalog. No hardcoded user-facing strings anywhere; module data that users read (e.g. cuisine names) is localized data, not code strings. (Logged as P5.)
9. **One dreamy design language** — soft gradients, glassmorphism, spring animations, tasteful haptics — defined once in the core theme and inherited by shell and modules alike. Original/generated art only; never lifted from another app. (Logged as P7.)

---

## 4. Platform Architecture

### Shared core (only what's actually shared)
- **Local persistence** — a store modules can read/write (e.g. a module's records). *(Built in v1: SwiftData container factory.)*
- **Themed shell (homepage)** — *evolved from the original "app shell / navigation" item.* The app opens into a lush couples space: full-bleed bright moonlit background (code-drawn full moon + particles), the two partner avatars + names in the **top corners**, and a centered **day-counter hero** — label line, huge day number, anniversary date — computed from our anniversary, with ambient motion (gentle parallax). *(Layout refined per P8, structure loosely following a reference the user shared; art stays original.)* With P11 the shell frame becomes a themed **bottom tab bar** of surfaces — **Home** (this couples space) and **Games** (the launcher) — and every future surface is one new tab.
- **Module launcher** — the shell's generic mechanism for mounting modules: the **Games tab's springboard grid** — app tiles plus user-arranged **collections** (iOS-folder style) with full jiggle-mode editing, layout kept per device in a small JSON document (P11, supersedes P8's trailing rail; doc: `docs/modules/games-springboard.md`); tapping a tile mounts that module's entry view. Food Decision is app #1.
- **Couple identity** — names, photos, anniversary date, stored in **local settings for now** (no pairing/sync — principle 2). Becomes synced core data if/when two-phone sync lands (§7).
- **Theme system** — the shared dreamy design language (principle 9) exposed as core tokens/components (colors, gradients, glass materials, motion curves, haptic patterns) that shell and modules consume.
- **Localization infrastructure** — one String Catalog covering en / zh-Hans / zh-Hant (principle 8). Language is switchable **both** ways: iOS's per-app language setting, and an in-app picker in the couple settings (System / English / 简体中文 / 繁體中文 — P9). The in-app override re-renders the UI live via the SwiftUI locale environment and aligns bundle lookups on next launch.
- **Not yet built (seams only):** pairing, cross-device sync, notifications. Left as clear extension points, not implemented.

### The Module Contract *(derived from module #1 — will firm up as #2 arrives; don't over-specify ahead of real need)*
A module is a self-contained feature. To plug into the platform it:
- **Exposes** an entry point (a SwiftUI view the launcher can mount) plus **tile metadata** (localized name + icon/emoji) for its launcher tile.
- **May persist** its own records through the core's persistence, using its own namespace.
- **Must not** depend on another module directly — modules are siblings, never a chain.
- **Hides external data sources behind a protocol** so the source is swappable without touching UI (e.g. module #1's `RestaurantProvider`).
- **Speaks the platform's languages** — all its user-facing strings live in the String Catalog; user-readable data is localized data.
- **Wears the platform's theme** — consumes core theme tokens rather than defining its own look. *(Food-decision adopts this in its v2 milestone; the contract binds new modules from day one.)*

That's the whole contract for now. It is intentionally minimal; we extend it only when a second module reveals a genuinely shared need.

---

## 5. Platform Decision Log (cross-module forks only)

Keep this to genuinely contested, cross-cutting decisions. Feature-level choices live in module docs. Never delete a row — supersede it with a new one referencing the old.

| # | Decision | Rationale | Rejected alternative |
|---|----------|-----------|----------------------|
| P1 | Native iOS + SwiftUI, iOS-only | Best native UI/feel; I already know SwiftUI; we only need iOS | React Native — only wins on cross-platform (not needed); adds a JS bridge and worse native feel |
| P2 | Modules over a thin core; build modules first, let the platform emerge | "Platform first" is the classic solo-dev trap — an empty framework has zero value until a loved feature runs on it | Building plugin/extension scaffolding before any module exists |
| P3 | Hand-written `.xcodeproj` with Xcode 16 synchronized folder groups; shared scheme committed | No tool dependency, $0; folders auto-sync so sessions add files without ever editing the project file; headless `xcodebuild` works | XcodeGen (extra Homebrew dependency); scaffolding via the Xcode GUI (blocks CLI-driven sessions) |
| P4 | Homepage is a **themed couples shell** with a swap-open frosted-glass **module launcher** (evolves the §4 "app shell" core item; home page is shared chrome, **not** a module) | The daily-open habit (§2) needs a home that feels like *ours*, not a menu; the launcher is the one generic mechanism any future module plugs into | A plain TabView/List home (functional but sterile); making the home page its own module (it's the frame around modules, so it can't be a sibling of them) |
| P5 | Full localization — en, zh-Hans, zh-Hant — via String Catalog, **from now on** | We live in all three; retrofitting localization is far costlier than building with it; String Catalog is the native, $0 mechanism | English-only now with a translation pass later (guarantees hardcoded-string debt and a painful sweep) |
| P6 | Couple identity (names, photos, anniversary) in **local settings** for now | Unblocks the shell while honoring local-first (principle 2); the data model is tiny and migrates cleanly into sync later | Building pairing/sync first just to share three fields (heavy, unproven need — the classic empty room) |
| P7 | Shared **theme system in the core** (gradient/glass/spring/haptic tokens) | One place to tune the feel; shell and modules stay visually coherent as the module count grows | Per-module ad-hoc styling (drifts apart within two modules); a third-party design system (needless dependency, less native feel) |
| P8 | Shell layout v2 (supersedes P4's layout, not its substance): launcher as a **trailing-edge side rail**; avatars in top corners; centered day-counter hero with anniversary date; **brighter** moonlit palette with a code-drawn full moon | The bottom drawer ate the vertical space the couple hero needs; structure loosely follows a reference app the user shared (2026-07-29) while all art stays original per principle 9 | Bottom drawer (shell v1); copying the reference's art (forbidden — layout inspiration only) |
| P9 | **In-app language picker** (System / English / 简体中文 / 繁體中文) in couple settings, alongside iOS's per-app language setting | Switching languages is part of this couple's daily reality; burying it in the Settings app adds friction — live `\.locale` override + AppleLanguages alignment gives instant switching with system consistency | System-setting-only localization (works, but invisible and slow to reach); a custom re-bundling scheme (needless complexity) |
| P10 | **Branching model**: `main` = production releases only; `develop` = integration (repo default). Every branch checks out from `develop`; PRs target `develop` and are **squash**-merged. Releases are a `develop → main` PR merged as a **merge commit — never squash** (squashing a release creates a commit `develop` lacks, permanently diverging the branches). Hotfixes: branch from `main`, then merge `main` back into `develop`. CI runs on pushes to `main`/`develop` (post-merge, not on PRs — a deliberate macOS-minutes trade-off) | Separates "what we run on our phones" from work-in-progress; a release becomes a deliberate, reviewable act instead of every merge being production | Single-branch trunk (every merge is instantly "released"); squash-merging releases (branch divergence trap); tag-based releases (heavier than needed for two people) |
| P11 | **Shell v3** (supersedes P8's *launcher*, keeps its home layout): a bottom **tab bar** of surfaces — **Home** + **Games** — where Games is a springboard-style grid of app tiles and user-arranged **collections** (folders) with full jiggle-mode editing; layout is a per-device JSON preference document; unregistered-in-layout modules auto-append | The rail tops out at a handful of tiles; tabs give every future surface a first-class slot, and the springboard with real iPhone-feel arranging makes launching playful and endlessly arrangeable (owners' explicit call 2026-07-29; 微爱's tab structure + iOS folders as layout reference only — art stays original per principle 9) | Keeping the trailing rail (doesn't scale past a few modules); context-menu or edit-sheet arranging (cheaper, but not the "real iPhone feel" the owners want); SwiftData for the layout (it's a preference document, not records) |
| P12 | **Development mode**: inline execution + one mandatory whole-branch review by default; full per-task subagent ceremony (fresh implementer + independent reviewer per task, "SDD") reserved for high-blast-radius work (schema/migrations, sync, concurrency, potential data loss) | Rigor proportional to risk: the final whole-branch review caught the severest bugs at a fraction of the cost, while per-task ceremony ran ~3–4× longer and dearer on work that was cheap to redo. We merge PRs quickly, so the agent review is the project's only real code review — it can shrink, never disappear | Full SDD on everything (v1–v2 practice: multi-hour, ~1M-token milestones regardless of risk); no review at all (unreviewed code straight to `develop`) |

*(Principles in §3 are not repeated here — the log is for forks with a rejected alternative worth remembering.)*

---

## 6. Module Index

| Module | Status | Doc |
|--------|--------|-----|
| Food decision ("what should we eat") | 🚧 v2 built — tri-language + Chinese search, in trial | `docs/modules/food-decision.md` |
| Games springboard (launcher surface — core shell chrome, documented module-style) | 🚧 v1 built — pending on-device feel pass | `docs/modules/games-springboard.md` |
| History (past decisions) | 📋 Planned *(supersedes the earlier "History / home page" row — the home page moved into the core shell, see P4)* | — |
| Two-phone sync (shared core capability) | 📋 Planned | — |
| Home-screen Widget | 📋 Planned | — |
| Daily notification | 📋 Planned | — |
| (future two-person mini-games, shared lists…) | 💡 Ideas | — |

*Adding a module = add a row here + a file in `docs/modules/`. If it needs a new shared capability, note it against the core in §4 and log the decision in §5.*

---

## 7. Roadmap Notes (cross-module, parked)

Revisited only after module #1 earns daily use:
- **Two-phone sync** becomes a *core* capability once any module needs to work while we're apart. **Direction chosen 2026-07-29, build deferred:** the app is now explicitly a shared two-person app, so sync is *when*, not *if*. Shape: local-first replication — SwiftData stays what the UI reads; a core-owned layer replicates records marked shared; modules never touch the network. Transport recommendation: **CloudKit shared zone (`CKShare` + `CKSyncEngine`)** — pairing is an iCloud share link (no accounts to build), free silent pushes, serverless, reachable from mainland-China networks; needs the $99/yr Apple Developer Program, which shipping requires anyway, so sync and "we pay" become one milestone. $0 fallback: the Aura WebSocket + SQLite pattern on the parcs server. Rejected: Firebase (third-party SDK against principle 1; unusable from mainland China). **Record hygiene from now on:** models expected to sync carry a stable `UUID` id, `updatedAt`, `authorID`, and soft-delete tombstones; conflict policy comes from data shape — last-writer-wins for settings, append-only union for history, turn-token for game state. When sync lands, **couple identity (P6) migrates from local settings into synced core data** — design the settings model so that move is mechanical.
- **Widget + daily notification** are core-adjacent capabilities that raise daily-open rate; worth doing once there's content worth surfacing.

---

## 8. Working Agreement (AI-assisted sessions)

- Start each session by reading this doc + the relevant module doc; confirm the milestone.
- **Branching (P10):** always branch from `develop`, PR back into `develop` (squash). `main` is production — it only moves via a `develop → main` release PR merged as a merge commit. Never branch new work from `main`.
- **Development mode (P11):** default is **inline execution + one mandatory whole-branch review** before the PR — the session implements directly (TDD for logic, suite green at every commit), then a single independent review of the full branch diff. Escalate to **full per-task subagent ceremony (SDD)** only for high-blast-radius work: SwiftData schema/migrations, sync, concurrency-heavy code, anything that could silently lose data. Never open a PR with zero independent review — the agent review is this project's only code review.
- Prompts are work orders: *"Build slice X per docs/modules/….md."*
- When a real decision is made, append it to the right log (platform §5, or the module's own log) **in the same session**.
- Explain module/file structure before generating code so seams can be checked.
- I'm an experienced full-stack/TypeScript engineer, newer to heavy SwiftUI — lean idiomatic modern SwiftUI, flag non-obvious bits (especially animation and localization machinery), favor readable well-separated code (this codebase keeps growing).
