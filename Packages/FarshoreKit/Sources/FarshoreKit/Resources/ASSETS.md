# Third-party assets in FarshoreKit

F9 permits licensed and CC0 assets and requires **consistent provenance**.
Every third-party file is listed here with its source and licence. A file not
listed here does not ship.

| File | Source | Licence |
|---|---|---|
| `ground_color.jpg` | ambientCG — Ground037 | CC0 |
| `ground_normal.jpg` | ambientCG — Ground037 (NormalGL) | CC0 |
| `ground_roughness.jpg` | ambientCG — Ground037 | CC0 |
| `ground_ao.jpg` | ambientCG — Ground037 | CC0 |
| `sky.hdr` | Poly Haven — kloofendal_43d_clear_puresky (2k) | CC0 |
| `sky_env.png` | Derived from `sky.hdr` (tone-mapped 8-bit equirect; see `IslandLook.swift`) — same source, same licence | CC0 |
| *(character slot — empty)* | Not yet supplied. `CharacterLoader.make(in:)` looks for `character.scn` in this folder and falls back to `MannequinCharacter` (built from SceneKit primitives in code — no asset, nothing to list here) when it is absent. The owner will export a rigged character plus Idle and Walking animations from Mixamo (their own Adobe account) as Collada `.dae` with skin, and **convert it to `character.scn`** — see below. **When that file is added, add its row here with Mixamo's actual licence terms for that account/export** — this row exists so the empty slot itself doesn't go unlisted, per F9's "a file not listed here does not ship." | n/a — no file present |

F9 also requires consistent provenance: every ground map above is from one
ambientCG set (`Ground037_1K`), so nothing reads as a mismatched mod-pack.

## Adding the character: `.dae` must be converted first

**Do not drop a raw `.dae` into this folder and expect it to load.** iOS has no
Collada importer. On macOS the importer runs in an out-of-process XPC service
(a failed load there says, verbatim, "Failed to retrieve scene from XPC
service"); no such service exists on iOS, so `SCNScene(url:)` on a valid `.dae`
throws `nilError` on both device and simulator. Collada is meant to be
converted to SceneKit's native format at build time.

This was measured, not assumed. Loading a Collada file written by SceneKit's
own macOS exporter on the iOS Simulator:

```
probe_raw.dae:          SCNScene FAILED -> nilError
probe_scntool_scn.scn:  SCNScene OK
```

### The command

From the repository root, with Xcode installed:

```bash
xcrun scntool --convert /path/to/mixamo-export.dae \
              --format scn \
              -o Packages/FarshoreKit/Sources/FarshoreKit/Resources/character.scn
```

Verified on this machine: the command succeeds, and its output loads on the
iOS Simulator with its animation clips intact and still carrying their authored
names (a two-clip source converted to a scene whose animation keys were
`["Hips:Walking", "Arm:Idle"]`). `scntool` ships inside Xcode at
`Contents/Developer/usr/bin/scntool`; `xcrun` locates it. `--format scn` is
accepted even though `scntool --help` advertises only `dae`, `c3d`, `usda`,
`usdc`, `usdz` — and it is genuinely validated, since an unknown format is
rejected with `scntool: error: Unknown conversion format`.

The GUI equivalent, if you'd rather: drag the `.dae` into Xcode, select it, and
choose **Editor ▸ Convert to SceneKit scene file format (.scn)**.

### Then

1. Make sure the result is named exactly `character.scn` and sits in this
   folder. That is the only filename `CharacterLoader` looks for.
2. Add its row to the table above, with Mixamo's licence terms for that export.
3. Nothing else — no code change. The mannequin stops appearing on its own.

If a file is present under an expected name but will not load, `CharacterLoader`
logs an error naming the file and repeating the command above, and falls back to
the mannequin. It does **not** fail silently; a silent fallback is what let a
non-working `.dae` instruction survive in four places at once.

### Textures

SwiftPM's `.process("Resources")` **flattens the directory tree** — every file
lands at the top level of the resource bundle, and sibling folders do not
survive as folders. A Mixamo export that ships `character.dae` alongside a
`textures/` subfolder will therefore break its own relative texture paths if
copied in wholesale.

`scntool` conversion is what saves you here: converting to `.scn` resolves and
embeds the material references at conversion time, so the single `character.scn`
is self-contained and there is nothing relative left to break. If a converted
character ever does render untextured, this flattening is the first thing to
suspect — and the fix is to convert with the `.dae` and its `textures/` folder
still in their original relative layout, then copy only the resulting `.scn`.
Any texture that must ship as a separate file needs its own row in the table
above, and a flat filename.
