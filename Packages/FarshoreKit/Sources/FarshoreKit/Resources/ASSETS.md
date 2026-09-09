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
| *(character slot — empty)* | Not yet supplied. `CharacterLoader.make(in:)` looks for `character.scn` in this folder, plus the optional `character-idle.scn` and `character-walk.scn`, and falls back to `MannequinCharacter` (built from SceneKit primitives in code — no asset, nothing to list here) when the rig is absent. The owner will export a rigged character plus Idle and Walking animations from Mixamo (their own Adobe account) as Collada `.dae`, and **convert each to `.scn`** — see below. **When those files are added, add a row here for each, with Mixamo's actual licence terms for that account/export** — this row exists so the empty slot itself doesn't go unlisted, per F9's "a file not listed here does not ship." | n/a — no file present |

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

`scntool` ships inside Xcode at `Contents/Developer/usr/bin/scntool`; `xcrun`
locates it. `--format scn` is accepted even though `scntool --help` advertises
only `dae`, `c3d`, `usda`, `usdc`, `usdz` — and it is genuinely validated, since
an unknown format is rejected with `scntool: error: Unknown conversion format`.

The GUI equivalent, if you'd rather: drag the `.dae` into Xcode, select it, and
choose **Editor ▸ Convert to SceneKit scene file format (.scn)**.

### Two shapes, because Mixamo gives you one animation per download

Mixamo does not generally hand you one file containing a rig and all its clips.
It hands you a character, and then a separate download per animation. Both
shapes work.

**Shape A — one file carrying the rig and its clips.** If your export really
does contain everything, this is all you need:

```bash
xcrun scntool --convert /path/to/mixamo-export.dae \
              --format scn \
              -o Packages/FarshoreKit/Sources/FarshoreKit/Resources/character.scn
```

**Shape B — a rig plus one file per animation.** This is the usual case. Run the
same command three times, changing only the output name:

```bash
RES=Packages/FarshoreKit/Sources/FarshoreKit/Resources

# The rig. Download this one WITH skin.
xcrun scntool --convert /path/to/character.dae --format scn -o "$RES/character.scn"

# The clips. These do NOT need skin — see the note below.
xcrun scntool --convert /path/to/idle.dae     --format scn -o "$RES/character-idle.scn"
xcrun scntool --convert /path/to/walking.dae  --format scn -o "$RES/character-walk.scn"
```

The filenames are exact. `character.scn` is the only required one; both clip
files are optional and are picked up automatically when present.

### With skin or without — the part people get wrong

- **The rig (`character.scn`) needs skin.** Download it **with skin**: it is the
  thing that has to render, so it needs the mesh.
- **The animation files do not.** An animation-only export needs to carry the
  clip and nothing else, so **without skin** is correct — and much smaller. If
  you download the clips with skin you get three copies of the same body, which
  works but bloats the app for no benefit.

### Precedence

**A dedicated clip file beats a same-role clip embedded in the rig.** If
`character.scn` already contains a Walking clip and you also supply
`character-walk.scn`, the separate file wins — supplying it is a deliberate act
and overriding is the only reason to do it. The two roles resolve
independently, so a rig with a usable idle plus a separate walk file is fine.

### Then

1. Check the filenames are exactly as above and the files sit in this folder.
2. Add a row to the table above for each file, with Mixamo's licence terms.
3. Nothing else — no code change. The mannequin stops appearing on its own.

All four shapes are supported and were verified end to end on the iOS Simulator
with real `scntool` output: rig-with-clips, rig-plus-separate-clips, rig-alone
(renders standing still), and nothing at all (the mannequin).

If a file is present under an expected name but will not load, the loader logs
an error naming the file and repeating the command above, and carries on: a bad
clip file falls back to the rig's own clip rather than taking the role down with
it, and a bad rig falls back to the mannequin. It does **not** fail silently; a
silent fallback is what let a non-working `.dae` instruction survive in four
places at once.

### If the character loads but moves wrongly

Everything below is a property of *your* two downloads, so no test in this
package can anticipate it. Work down the list.

| What you see | Likely cause | Fix |
|---|---|---|
| The whole body rotates or slides **as one rigid piece**, limbs not articulating, while it still faces the way it walks | The clip's bone names do not match the rig's, so SceneKit cannot retarget it and animates the rig container instead | Re-download the rig and the clips from the **same Mixamo character**, so the skeletons match |
| It stands in its bind pose, no movement at all | No clip was found | Check the filenames, and the log — the loader names any file it could not use |
| It walks backwards, facing away from travel | Rig faces local −Z | `RiggedCharacter.riggedForwardOffset = .pi` |
| It travels sideways relative to where it points | Rig faces local ±X | `riggedForwardOffset = ±.pi / 2` |
| Enormous, or the camera is inside it | Export authored in centimetres | `RiggedCharacter.riggedScale = 0.01` |

The first row is worth reading twice, because it is the one that looks like an
animation problem and is actually a *pairing* problem. It is also the one whose
symptom was described wrongly in an earlier draft of this document: a clip whose
bones do not resolve does **not** leave the character standing still, it moves
the whole body rigidly. That was measured, not assumed.

Note that the character's facing is protected either way — a clip can no longer
overwrite it, because clips are attached below the node that carries facing. So
"it faces the right way but moves like a statue on a turntable" is a coherent
and expected combination, not two separate bugs.

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
