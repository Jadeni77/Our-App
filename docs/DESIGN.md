# DESIGN.md — Platform (extensible two-person iOS app)

> **Source of truth for the whole app.** This is the *platform* doc — it holds only what's true across every module. Per-module detail lives in `docs/modules/`. Read this at the start of every session, then read the doc for whatever module you're working on.
>
> **How this doc stays small:** anything specific to one feature goes in that module's doc, not here. Adding a new feature = a new file in `docs/modules/` + a new row in the Module Index (§6). This doc should barely change once a module exists.
>
> Prompts are work orders derived from these docs, e.g. *"Build milestone-1 slice per docs/modules/food-decision.md."*

---

## 1. Vision

A small, native iOS app my partner and I use daily — **not** a big app, but a growing set of tiny, high-quality **modules** sharing a thin common **core**. The platform grows *out of* building real modules; we never build framework ahead of a feature that needs it.

Module #1 (current work) helps us decide what to eat. Future modules are listed in §6.

---

## 2. Goals & Non-Goals (platform level)

**Goals:** be something we actually open daily; keep a clean foundation so new modules slot in without rewrites; stay free to build and run until we choose to ship.

**Non-Goals:** not a big app (depth over breadth); not social / multi-couple / public; not cross-platform.

---

## 3. Design Principles (durable rules every decision is checked against)

1. **iOS-native first** — Swift/SwiftUI, native APIs, native feel. No cross-platform layer.
2. **Local-first until proven** — no backend / sync / accounts until a feature clearly needs it *and* daily use has justified the cost.
3. **Ultra-short interactions** — minimize taps; each module is a quick ritual, not a form.
4. **Free until ship** — \$0 to build and test; pay only when earned (App Store / permanent install).
5. **Modules over a thin core** — features are self-contained, talk through narrow interfaces; the core stays small and holds only what's genuinely shared.
6. **Build the feature, grow the platform** — never scaffold platform ahead of a real module. Leave clean seams; don't build empty rooms.
7. **Fail soft** — permission denials and empty states degrade to friendly messages, never dead ends.

---

## 4. Platform Architecture

### Shared core (only what's actually shared)
- **Local persistence** — a store modules can read/write (e.g. a module's records).
- **App shell / navigation** — where modules mount and how the user moves between them.
- **Not yet built (seams only):** pairing, cross-device sync, notifications. Left as clear extension points, not implemented.

### The Module Contract *(derived from module #1 — will firm up as #2 arrives; don't over-specify ahead of real need)*
A module is a self-contained feature. To plug into the platform it:
- **Exposes** an entry point (a SwiftUI view the shell can mount).
- **May persist** its own records through the core's persistence, using its own namespace.
- **Must not** depend on another module directly — modules are siblings, never a chain.
- **Hides external data sources behind a protocol** so the source is swappable without touching UI (e.g. module #1's `RestaurantProvider`).

That's the whole contract for now. It is intentionally minimal; we extend it only when a second module reveals a genuinely shared need.

---

## 5. Platform Decision Log (cross-module forks only)

Keep this to genuinely contested, cross-cutting decisions. Feature-level choices live in module docs. Never delete a row — supersede it with a new one referencing the old.

| # | Decision | Rationale | Rejected alternative |
|---|----------|-----------|----------------------|
| P1 | Native iOS + SwiftUI, iOS-only | Best native UI/feel; I already know SwiftUI; we only need iOS | React Native — only wins on cross-platform (not needed); adds a JS bridge and worse native feel |
| P2 | Modules over a thin core; build modules first, let the platform emerge | "Platform first" is the classic solo-dev trap — an empty framework has zero value until a loved feature runs on it | Building plugin/extension scaffolding before any module exists |
| P3 | Hand-written `.xcodeproj` with Xcode 16 synchronized folder groups; shared scheme committed | No tool dependency, $0; folders auto-sync so sessions add files without ever editing the project file; headless `xcodebuild` works | XcodeGen (extra Homebrew dependency); scaffolding via the Xcode GUI (blocks CLI-driven sessions) |

*(Principles in §3 are not repeated here — the log is for forks with a rejected alternative worth remembering.)*

---

## 6. Module Index

| Module | Status | Doc |
|--------|--------|-----|
| Food decision ("what should we eat") | 🚧 v1 built — in real-use trial | `docs/modules/food-decision.md` |
| History / home page | 📋 Planned | — |
| Two-phone sync (shared core capability) | 📋 Planned | — |
| Home-screen Widget | 📋 Planned | — |
| Daily notification | 📋 Planned | — |
| (future two-person mini-games, shared lists…) | 💡 Ideas | — |

*Adding a module = add a row here + a file in `docs/modules/`. If it needs a new shared capability, note it against the core in §4 and log the decision in §5.*

---

## 7. Roadmap Notes (cross-module, parked)

Revisited only after module #1 earns daily use:
- **Two-phone sync** becomes a *core* capability once any module needs to work while we're apart. Options: CloudKit (native, serverless, simplest) or reuse the WebSocket + SQLite pattern from Aura on the parcs server. Decide when a module actually needs it.
- **Widget + daily notification** are core-adjacent capabilities that raise daily-open rate; worth doing once there's content worth surfacing.

---

## 8. Working Agreement (AI-assisted sessions)

- Start each session by reading this doc + the relevant module doc; confirm the milestone.
- Prompts are work orders: *"Build slice X per docs/modules/….md."*
- When a real decision is made, append it to the right log (platform §5, or the module's own log) **in the same session**.
- Explain module/file structure before generating code so seams can be checked.
- I'm an experienced full-stack/TypeScript engineer, newer to heavy SwiftUI — lean idiomatic modern SwiftUI, flag non-obvious bits, favor readable well-separated code (this codebase keeps growing).
