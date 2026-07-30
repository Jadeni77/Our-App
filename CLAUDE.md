# OurApp — session context (read this first)

**Before any work: read `docs/DESIGN.md` (platform source of truth), then the doc in
`docs/modules/` for whatever module you're touching.** Decision logs there are
append-only — never reopen a logged decision (P#/F# rows); supersede with a new row.

## Hard rules

- **Branching (P10):** branch from `develop`, PR into `develop` (squash). `main` is
  production — it only moves via a `develop → main` release PR merged as a
  **merge commit, never squash**. Never branch new work from `main`.
- **Commits/PRs:** plain imperative English, **no AI attribution of any kind**
  (no Co-Authored-By trailers, no "Generated with" footers). PRs follow
  `.github/pull_request_template.md` (Description / Solution / Testing / Proof).
- **Localization (P5/principle 8):** every user-facing string ships in en, zh-Hans,
  and zh-Hant via `OurApp/Resources/Localizable.xcstrings`; user-readable data is
  localized data. Views resolve cuisine names via `\.locale` (in-app picker, P9).
- **$0 rule:** no packages, no paid APIs. Synchronized folder groups — never edit
  `project.pbxproj` to add files.

## Build & test

```
xcodebuild test -project OurApp.xcodeproj -scheme OurApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

CI runs on pushes to `main`/`develop` only (no PR trigger — deliberate).

## When decisions get made

Append them to the right log **in the same session**: platform forks → DESIGN.md §5;
module forks → that module doc's decision log (per working agreement §8).
