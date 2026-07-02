# Art Generator Spec — Phase 8.A in detail

> Companion to `IMPLEMENTATION_GUIDE.md` Phase 8.A. That file says *what* and
> *in which order*; this file says *exactly how* — algorithms, color math,
> naming conventions, integration points, and the traps already identified in
> the current code. Follow this spec; where a number is marked *(tune)*, you
> may adjust it after looking at the contact sheet, one change at a time.
>
> Scope: `_assets_gen.gd` (generator), `scripts/MapView.gd` (consumption),
> `scripts/Hud.gd` + `scripts/Ui.gd` (icons / 9-patch). No gameplay logic.

---

## 0. Ground rules & traps (read first)

### 0.1 Per-sprite RNG determinism (fix this before anything else)
The generator uses ONE global `rng` seeded once (`rng.seed = 1337`,
_assets_gen.gd:50). Consequence: **adding a single `rng.randf()` call
anywhere changes every sprite generated after it** — diffs become
unreviewable and variants are impossible to pin.

Fix: at the top of every `_gen_*` function (and every variant/frame), reseed
deterministically:

```
rng.seed = hash("gobelin")            # sprite identity
rng.seed = hash("plaine_ground_2")    # identity includes variant index
rng.seed = hash("campfire_f1")        # identity includes frame index
```

Rule: the seed string == the output filename (minus `.png`). After this, any
sprite can be regenerated in isolation and PNG diffs only show what you
actually changed. Do this as commit #1 of the phase; expect a one-time diff
of most PNGs (accept it, review via contact sheet).

### 0.2 Import cache
After every regeneration run, re-run the editor import pass
(`--headless --editor --quit --path .`) or newly created files are invisible
to `load()` and fall back silently to ASCII glyphs.

### 0.3 Compatibility names
`MapView._load_textures`, `TownView`, `Hud._sprite_portrait` look up sprites
by exact name. Every new naming scheme below keeps the legacy name working
(either still saved, or used as fallback). Never delete a legacy name in the
same commit that introduces its replacement.

### 0.4 `gen.py`
Must be frozen/deleted (guide Phase 7.4) **before** this work. Do not mirror
any of this into Python.

---

## 1. Hue-shifted ramps

### 1.1 The helper
Godot `Color.darkened()/lightened()` lerp toward black/white — same hue, less
saturation life. Replace with ramps built in HSV.

```
# Returns 5 colors, index 0 = darkest … 4 = lightest, base at index 2.
func _ramp(base: Color) -> Array[Color]
```

Anchors (constants):
- `SHADOW_HUE := 0.6875`  — the hue of INK (indigo). Derived from
  INK = (0.055, 0.050, 0.090); do not recompute at runtime, hardcode it.
- `WARM_HUE := 0.115`     — warm candle-light (orange-gold).

Per step, with `h/s/v` = base color's HSV (`base.h`, `base.s`, `base.v`):

| i | v (value) | s (saturation) | h (hue) |
|---|---|---|---|
| 0 | `v*0.40 + 0.01` | `min(1, s*1.10 + 0.05)` | toward SHADOW_HUE by **0.10** |
| 1 | `v*0.65 + 0.01` | `min(1, s*1.12 + 0.04)` | toward SHADOW_HUE by **0.05** |
| 2 | v | s | h (base, unchanged) |
| 3 | `min(1, v*1.25 + 0.06)` | `s*0.78` | toward WARM_HUE by **0.03** |
| 4 | `min(1, v*1.45 + 0.15)` | `s*0.50` | toward WARM_HUE by **0.05** |

*(all shift amounts: tune ±0.02 after contact-sheet review)*

Hue shifting must take the **shortest wrap-around path**:

```
func _hue_toward(h: float, target: float, amt: float) -> float:
    var d := fposmod(target - h + 0.5, 1.0) - 0.5   # signed shortest delta
    return fposmod(h + clampf(d, -amt, amt), 1.0)
```

Special cases:
- **Near-gray materials** (`s < 0.08`: STEEL, BONE, STONE): skip the warm
  shift entirely (steel highlight going yellow reads as brass); apply only
  half the shadow shift. Highlight steps instead push v harder
  (`i=4: v*1.55 + 0.20`).
- **Already-neon accents** (CYAN, EMBER, ARCANE_L used as glows): do not
  ramp them — glows keep their exact identity colors.
- Rebuild with `Color.from_hsv(h, s, v, base.a)`.

### 1.2 The RAMPS table
One static dictionary, materials → precomputed ramps (computed once in
`_init` after the helper exists):

```
RAMPS = {
  "skin": _ramp(SKIN), "rose": _ramp(ROSE), "steel": _ramp(STEEL),
  "bone": _ramp(BONE), "gold": _ramp(GOLD), "blood": _ramp(BLOOD),
  "arcane": _ramp(ARCANE), "poison": _ramp(POISON), "ember": _ramp(EMBER),
  "wood": _ramp(PROP_WOOD), "stone": _ramp(STONE),
}
```

Accessor `func R(mat: String, i: int) -> Color`. Biome-driven colors
(trunk/leaf/rock/water from `Data.BIOMES`) get ramps built at call time
inside `_gen_tree/_gen_rock/_gen_water`: `var lf := _ramp(leaf)` and then use
`lf[0..4]` instead of the current `leaf.darkened(0.42)` etc. mapping:

- old `X.darkened(0.4..0.6)` → `ramp[0]`
- old `X.darkened(0.15..0.3)` → `ramp[1]`
- old `X` → `ramp[2]`
- old `X.lightened(0.18..0.3)` → `ramp[3]`
- old `X.lightened(0.4..0.5)` → `ramp[4]`

Migration order: tiles first (`_gen_ground`, `_gen_tree`, `_gen_rock`,
`_gen_water`, `_gen_road`) — they cover most screen pixels; then props; then
creatures opportunistically (full creature sweep happens in the 8.B redraws;
do NOT hand-convert all 45 figures now).

### 1.3 Palette report
At the end of `_init`, scan every saved PNG:
- Count only pixels with `a >= 0.999` (the `_glow` blends legitimately create
  hundreds of intermediate alpha colors — exclude them).
- Quantize to 6 bits/channel before counting distinct colors.
- Print: total distinct opaque colors, and the top 10 files by distinct
  count. **Warn** (stdout) above 64 total; do not fail the build yet.

---

## 2. Selective outline pass (`_auto_outline`)

### 2.1 Algorithm (inline outline — does not grow the canvas)
```
func _auto_outline(img: Image) -> void
```
1. Build mask: `inside(x,y) := alpha(x,y) > 0.5`.
2. For every inside pixel with at least one 4-neighbor outside
   (or at the image border): it's an edge pixel.
3. Recolor edge pixels by direction of exposure:
   - exposed **below** (or bottom image row): `INK` (full outline weight —
     this is the shadow/ground side);
   - exposed **right** only: `current.lerp(INK, 0.75)`;
   - exposed **top or left** only (lit side): `current.lerp(INK, 0.45)` —
     a *soft* selout, keeps the sprite from looking sticker-like.
   - If exposed on multiple sides, the strongest rule wins (below > right >
     top/left).
4. Skip recoloring if the pixel is already ≈ INK
   (`current.lerp-dist to INK < 0.08` on RGB) — figures that hand-drew their
   outline aren't double-darkened.

Implementation notes:
- Compute the mask FIRST into a `PackedByteArray`, then recolor — otherwise
  recolored pixels corrupt neighbor tests mid-pass.
- Run **after** the figure function, **before** final glow accents. Concretely
  in `_gen_creature`: `fig(img)` → `_auto_outline(img)` → re-stamp eye glows
  (extract the 1-2 `_glow_eyes`/accent-glow calls so they can be re-applied
  after outlining; simplest: figure functions take an optional
  `accents_only := false` flag, or accept the slight dimming — check on the
  contact sheet which is needed).

### 2.2 Exemptions
Ethereal creatures must keep soft edges: `spectre`, `banshee`, `ame`,
`seigneur_fantome`, `fee`, `oeil_neant` → outline **bottom side only** (rule
3a), skip lit sides entirely. Maintain an explicit exemption list next to
`_gen_creature`'s match table.

Apply `_auto_outline` to creatures and props. Do NOT apply to full-bleed
terrain tiles (ground/water/road) — they have no silhouette.

---

## 3. Ground variants (kills the tiling grid)

### 3.1 Generator
- `_gen_ground(a, b, variant: int)` — same recipe; the reseed rule from §0.1
  (`hash("plaine_ground_2")`) makes each variant's noise/speckle placement
  unique. Additionally vary per variant: speckle probability ±30 %, and
  offset the two `(x*5+y*3)%17`-style deterministic patterns by `variant`.
- Save `"%s_ground_%d" % [id, v]` for v in 0..3, **plus** legacy
  `"%s_ground"` (copy of variant 0) for TownView/fallbacks.

### 3.2 Kill the baked-in grid seams
`_gen_ground` currently draws joint lines along x=0/y=0 and a darkened last
row/col (_assets_gen.gd:1417-1443) — dungeon-flagstone logic that makes
open-world grass read as a grid. Change to:
- Remove the x=0 / y=0 joint lines and the mid-tile (16) joints entirely.
- Keep only the bottom/right edge darkening, reduced to **8-12 % opacity**
  lerp toward INK_SOFT *(tune — may go to zero if variants alone break the
  grid)*.

### 3.3 MapView selection
In `_draw_ground` (MapView.gd:357): pick
`"%s_ground_%d" % [bid, (x * 7 + y * 13) % 4]`, fallback to `"%s_ground"`,
then existing color-rect fallback. The hash must be position-stable and
asymmetric (NOT `(x+y)%4`, which produces diagonal stripes). No RNG here —
`_draw` runs every frame.

---

## 4. Water shoreline autotiling

### 4.1 Tile set (cardinal 4-bit, 16 tiles)
For a WATER cell, `mask = N*1 + E*2 + S*4 + W*8` where a bit is 1 when that
neighbor is **land** (any non-WATER tile; out-of-bounds counts as land).
Generate 16 images per biome: `"%s_water_e%d" % [id, mask]`; `e0` is the
open-water tile (current `_gen_water` output). Keep legacy `"%s_water"` =
copy of `e0`.

Diagonals are deliberately ignored in v1 (cost: a missing 1px notch on
outer corners — acceptable; upgrade path is the 47-tile blob set later).

### 4.2 Bank rendering (per land-facing edge)
On each edge whose bit is set, paint inward from that edge:
- row/col 0 (touching land): waterline — `water_base.darkened(0.35)` (reuse
  ramp index 0) — reads as the dark wet lip;
- row/col 1: `crest` color (existing lightened wave color) as a broken line:
  skip pixels where `(x*3+y*7)%4 == 0` so the foam looks irregular;
- row/col 2: 3-4 sparse foam pixels `Color(1,1,1,0.55)` placed by the
  (reseeded) rng.
Corners where two set edges meet: just let both passes overlap — the double
paint is the corner treatment.

### 4.3 MapView integration
`_draw_terrain` WATER branch (MapView.gd:333): compute the mask from
`dungeon.tiles` neighbors, try `"%s_water_e%d"`, fall back to `"%s_water"`,
then color rect. Cheap (4 array lookups); no caching needed.

### 4.4 Reuse
Volcan's "water" IS lava (orange). The same edge set gives lava banks for
free; add `_glow` along lava edges (strength 0.35) inside the generator when
`water color`'s hue is warm (`h < 0.2`). Phase 4's frozen-water tiles will
reuse this exact mechanism — build it clean.

### 4.5 Road blending (same spirit, simpler)
Roads currently render as opaque squares (`_gen_road` fills the tile). Make
the road an **overlay**: dither its outer 3-4 px ring to transparency
(Bayer-thresholded alpha falloff), and change MapView's ROAD branch to draw
the biome ground first, then blit the road overlay. One tile works for all
biomes and the hard square edge disappears. Keep legacy behavior as fallback
if the ground blit fails.

---

## 5. Tall trees (canopy overlap)

- Generate trees on a **32×48** canvas (`_new_sized(32, 48)`), feet anchored
  in the bottom 32×32, canopy using the extra 16 top rows. All current
  y-coordinates in `_gen_tree` shift down by +16.
- MapView TREE branch: if the tree texture's height > CELL, blit into
  `Rect2(x*CELL, y*CELL - (h_px - CELL) * (CELL/32.0), CELL, h_px * (CELL/32.0))`
  (bottom-anchored). Since `_draw` iterates rows top-to-bottom, a tree
  correctly overlaps the already-drawn row above it.
- **Fog guard**: only use the tall blit when the cell above
  (`y-1`) is explored; otherwise draw clipped to the cell rect (a canopy
  poking into unexplored blackness leaks information). One `if` — do not
  skip it.
- **Known accepted artifact (v1)**: entities are drawn after terrain, so a
  unit standing at `y-1` draws over the canopy of the tree at `y` instead of
  behind it. Accept and note it; proper y-sorting is a v2 (interleave
  terrain/entity rows) and not worth it yet.

---

## 6. Animation frames

### 6.1 Convention
- Files: `name_f0.png`, `name_f1.png`, … Static `name.png` continues to work
  everywhere (fallback), so rollout is per-sprite and zero-risk.
- `MapView._load_textures`: after loading `name`, probe `name_f0..f3`; if
  found, store `anim[name] = [frames]`.
- `_blit` family: if `anim.has(name)`, select
  `frames[int(_anim_t / 0.45) % frames.size()]` *(0.45 s cadence, tune)*.
  For **entities**, offset the phase by `e.get_instance_id() % frames.size()`
  so units don't breathe in sync.

### 6.2 What gets frames (and what changes per frame)
| Sprite | Frames | Delta between frames |
|---|---|---|
| water (all 16 edge tiles) | 2 | wave phase `+3 px` horizontal shift; foam pixels toggle |
| campfire | 3 | flame `_tri_up` heights ±2 px, tip sway ±1 px, glow strength 0.5↔0.7, ember pixels reshuffled (rng reseeded per frame) |
| lantern_post, `ember`/`wisp`/`crystal` decors | 2 | glow strength pulse 0.45↔0.7, core highlight toggles |
| aria / aria_back / aria_side | 2 | chest row +1 px, hair tip +1 px, pendant glow pulse |
| the 10 bosses | 2 | 1-2 px signature element shift (crown, eye, flame) + glow pulse |

Common enemies stay single-frame until the 8.B wave-4 redraws.

Implementation: `_gen_*` concerned gain a `frame := 0` parameter; the
`_init` save list loops frames. Reseed rule (§0.1) uses the full name
including `_f1`, EXCEPT where frames must share placement (campfire logs must
not move between frames!) — pattern: seed with the base name, draw the static
part, then reseed with the frame name for the animated part.

---

## 7. Creature composition kit

### 7.1 Stamp API (extract from the best existing figures)
All stamps take an explicit ramp and return anchor points:

```
_body_biped(img, ramp, o={h:16, hips:5.0, feet_y:29, legs:"boots"}) -> {head, hand_l, hand_r, chest}
_body_quadruped(img, ramp, o={len:18, h:9})                          -> {head, back}
_body_robed(img, ramp, o={hem:9.0})                                  -> {head, hand_l, hand_r, chest}
_head_round(img, at, ramp, r=4.5)      # + optional ears/horns opts
_head_hooded(img, at, ramp)
_head_skull(img, at)                   # uses RAMPS.bone
_weapon_stamp(img, hand, kind, ramp)   # kind: sword|axe|dagger|bow|staff|club
_emblem(img, at, color)                # chest diamond + glow (Aria's pattern)
_glow_eyes(img, cx, ey, c, spread)     # exists — keep
```

Every stamp starts from the proven recipes in `_fig_aria`/`_fig_orc`/
`_fig_gobelin` (trapezoid body + banded shading + contact shadow) — this is
extraction, not invention. `_ground_shadow` is called by the body stamps,
never by the composer.

### 7.2 Proof-of-concept conversions (required)
Rebuild exactly these five with the kit, compare on the contact sheet
against the old renders, and only then declare the kit done:
`gobelin` (small biped + dagger), `kobold` (small biped + ears),
`brigand` (biped + hood + bow), `cultiste` (robed + hood + emblem),
`zombie` (biped, torn silhouette: 2-3 bites taken out of the trapezoid with
transparent px after outlining).

Do NOT convert: `aria*` (bespoke, 3 views), bosses (bespoke), non-humanoids
(spider/wolf/serpent/drake…) until a quadruped/serpent stamp proves itself.

### 7.3 Variant hooks (free wins, wire now, use later)
`_gen_creature(kind, opts={})` accepts `{"tint": Color, "scale_glow": bool}`:
- `tint`: post-pass that hue-shifts the sprite's dominant ramp toward the
  tint (elite variants — guide Phase 6.2 consumes this);
- legendary: re-render with an extra `_glow` aura pass, saved as
  `<kind>_leg.png` (MapView picks it for `is_legendary` entities when it
  exists).

---

## 8. Contact sheet & readability validator

### 8.1 Contact sheet (`assets_preview.png`)
- Generated at the END of `_init`, always.
- Layout: 12 columns; cell = 40×56 px; sprites alphabetical. Each cell draws
  the sprite twice side-by-side isn't possible in 40px — instead produce TWO
  sheets: `assets_preview_dark.png` (cells filled `COLOR_FOG`-ish
  `(0.015,0.012,0.028)`) and `assets_preview_ground.png` (cells filled with
  the plaine ground tile, tiled).
- Headless `Image` has no text: print the index map to stdout
  (`row,col → name`) so a sheet position is identifiable.
- Add a third sheet `assets_preview_biomes.png`: for each biome, one row —
  4 ground variants, water e0/e5/e10, tree, rock, the 3 decors — to judge
  terrain cohesion per biome at a glance.
- Commit the sheets. Every art PR shows its visual diff for free.

### 8.2 Readability validator (`_art_check.gd`, standalone SceneTree script)
For each creature sprite × each biome ground tile:
1. Composite sprite over the tiled ground.
2. Edge ring = inside pixels (α>0.5) with an outside 4-neighbor.
3. `L = 0.2126r + 0.7152g + 0.0722b` (Rec. 709).
4. `edge_contrast = |mean_L(edge ring) − mean_L(ground pixels in the sprite's
   bbox, outside the silhouette)|`.
5. `body_contrast` = same with all inside pixels.
6. **Fail** the pair if `edge_contrast < 0.10 AND body_contrast < 0.12`
   *(tune once against the known-good current set — thresholds must pass
   today's sprites except any that genuinely look wrong)*.
- Output: table of the 10 worst pairs + pass/fail; exit code ≠ 0 on fail.
- Run it in CI right after generation (guide Phase 7.1), and locally after
  every regen.

---

## 9. UI coherence: icons & 9-patch

### 9.1 Pixel icon set (replaces emoji)
Generate 16×16 icons (own section in `_assets_gen.gd`, INK outline, one
accent glow max, transparent bg): `icon_atk` (sword), `icon_magic` (spark),
`icon_def` (shield), `icon_speed` (bolt), `icon_regen` (heart),
`icon_vision` (eye), `icon_crit` (burst), `icon_dodge` (swirl),
`icon_lifesteal` (drop), `icon_shards` (gem), `icon_bank` (chest);
statuses: `icon_st_poison`, `_burn`, `_bleed`, `_disease`, `_slow`, `_stun`,
`_weaken`, `_confusion`.

Hud changes: `STAT_ICONS` rows gain the icon name; `_stat_cell` swaps the
glyph Label for a TextureRect (`TEXTURE_FILTER_NEAREST`, 16→scaled to fit)
with the old glyph kept as fallback when the PNG is missing. Same swap in
`STATUS_LABEL` rendering. Grep the HUD for remaining emoji afterwards —
target: zero emoji in `Hud.gd`/`Ui.gd` strings (building names in `Town.gd`
keep their glyphs only if still used anywhere visible — replace with the
building sprites/icons).

### 9.2 9-patch panels
- Generate `panel_9p.png` (12×12): 1px INK border; inside it 1px bevel —
  `STONE_L` top/left, `STONE_D` bottom/right; fill `(0.072,0.065,0.115)`
  (current sidebar bg). Corner margin: 4 px.
- `button_9p.png` + `button_9p_hover/pressed/disabled` variants: same
  construction, border color ACCENT-family per state (reuse the exact colors
  from `Ui._style_button`).
- `Ui.panel_style/card_style/_btn_box` get StyleBoxTexture-based versions
  (`texture_margin_* = 4`, no corner radius, **no shadow** — flat is the
  style; the current soft shadows go away deliberately).

---

## 10. Execution order & checkpoints

Each checkpoint = regenerate → import pass → contact sheets → one in-game
xvfb screenshot → smoke test green → commit (sheets included).

1. **C1 — Plumbing**: per-sprite reseeding (§0.1) + contact sheets (§8.1).
   Expect a big one-time PNG diff; eyeball the sheets for regressions.
2. **C2 — Ramps**: `_ramp`/`_hue_toward`/`RAMPS` + palette report (§1) +
   convert the 5 tile generators (ground/tree/rock/water/road). Screenshot
   forêt + toundra: shadows should read violet-ish, highlights warm.
3. **C3 — Outlines**: `_auto_outline` + exemption list (§2). Sheet check:
   uniform edges, ghosts still soft.
4. **C4 — Ground variants + seam removal** (§3). Screenshot: no visible
   grid on open grass.
5. **C5 — Water/lava shorelines + road overlay** (§4). Screenshot: marais
   (many banks) + volcan (lava glow edges).
6. **C6 — Tall trees** (§5). Screenshot: forêt treeline; verify the fog
   guard at an exploration frontier.
7. **C7 — Animation** (§6). Two screenshots 0.5 s apart: water + campfire
   differ; Aria breathes.
8. **C8 — Composition kit + the 5 conversions** (§7).
9. **C9 — Validator wired into CI** (§8.2).
10. **C10 — Icons + 9-patch** (§9). Screenshot: sidebar with pixel icons,
    no emoji, crisp panel borders.

At C10, Phase 8.A is done → produce the full before/after screenshot set
(title, hub, one floor per biome) and STOP for the human 32-vs-64 decision
(guide §8.B).
