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
| *(character slot — empty)* | Not yet supplied. `CharacterLoader.make(in:)` looks for `character.scn` then `character.dae` in this folder and falls back to `MannequinCharacter` (built from SceneKit primitives in code — no asset, nothing to list here) when neither is present. The owner will export a rigged character plus Idle and Walking animations from Mixamo (their own Adobe account) as Collada `.dae` with skin. **When that file is added, add its row here with Mixamo's actual licence terms for that account/export** — this row exists so the empty slot itself doesn't go unlisted, per F9's "a file not listed here does not ship." | n/a — no file present |

F9 also requires consistent provenance: every ground map above is from one
ambientCG set (`Ground037_1K`), so nothing reads as a mismatched mod-pack.
