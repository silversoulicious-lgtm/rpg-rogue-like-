# Implementation Guide — « Les Strates »

> **Purpose**: self-contained work order for an AI agent (or any developer)
> executing the findings of `AUDIT.md` (bugs & issues) and `VISION.md`
> (differentiation & polish). This file specifies *exactly how* — algorithms,
> integration points, data shapes, known traps — not just what. Where a
> number is marked *(tune)* you may adjust it after observing the result,
> one change at a time. `ART_GENERATOR_SPEC.md` plays the same role for the
> art phase.
>
> **Read this entire file before writing any code.**

---

## 0. Project context (what you are working on)

- **Game**: « Les Strates » — turn-based roguelike in **Godot 4.3 / GDScript**.
  One heroine (Aria) climbs an Aincrad-style tower. Weapon type (melee/ranged/
  magic) defines the build. Linear floor progression with random node types
  (combat / elite / shop / event / rest), a guaranteed Guardian boss every
  act, permadeath, meta-progression between runs (Shards bank, Knowledge
  tree, Oaths), procedural loot with rarities/affixes/prefixes/unique items.
- **Everything player-facing is in FRENCH** (UI text, item names, messages,
  commit messages, README). Keep it that way.
- **All art is code-generated** pixel sprites (32×32) in `assets/*.png`,
  produced by `_assets_gen.gd`. `gen.py` is a legacy Python mirror (frozen in
  Phase 7.4).
- `scenes/Main.tscn` is a single node; the whole game is built in code.

### File map

| File | Role | Size |
|---|---|---|
| `scripts/Main.gd` | God object: state machine, floor generation, combat, enemy AI, skills, loot, shop/events/rest, turn loop | ~2 180 lines |
| `scripts/Hud.gd` | ALL UI: sidebar, log, title, loadout, meta screens, overlays | ~1 075 |
| `scripts/Data.gd` | Static data: heroine, 25 enemies, 10 bosses, skills, items, affixes, prefixes, uniques, talents, artifacts, powers, events, upgrades, knowledge tree, oaths | ~890 |
| `scripts/Entity.gd` | Pure-data grid entity + derived stats + statuses | ~290 |
| `scripts/Dungeon.gd` | Procedural open-world floor gen + fog of war | ~265 |
| `scripts/GameState.gd` | Autoload: persistent meta, JSON save (`user://save.json`) | ~175 |
| `scripts/MapView.gd` | Tile/entity rendering, fog, camera, FX layer, atmosphere | ~430 |
| `scripts/Town.gd` / `TownView.gd` | Hub model + renderer | ~155 |
| `scripts/Ui.gd` | Widget factory (labels/buttons/styles) | ~150 |
| `scripts/EquipPanel.gd`, `TitleBg.gd` | Sidebar equipment silhouette; title backdrop | small |
| `_smoketest.gd` + `_SmokeTest.tscn` | Headless smoke test driving full runs | ~710 |
| `_assets_gen.gd` | Sprite generator (art source of truth) | ~2 190 |

### Tooling — build, test, verify

```bash
# 1. Godot 4.3 headless (Linux):
curl -sSL -o godot.zip https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip
unzip -q godot.zip && chmod +x Godot_v4.3-stable_linux.x86_64

# 2. MANDATORY first run — populates class cache & imports assets.
#    Re-run after generating any new PNG, or on "Identifier not declared":
./Godot_v4.3-stable_linux.x86_64 --headless --editor --quit --path .

# 3. Smoke test (must print "=== SMOKETEST PASSED ==="):
./Godot_v4.3-stable_linux.x86_64 --headless --path . res://_SmokeTest.tscn

# 4. Regenerate sprites after editing _assets_gen.gd:
./Godot_v4.3-stable_linux.x86_64 --headless --path . --script res://_assets_gen.gd

# 5. Real rendering / screenshots (headless = dummy driver, zero pixels):
#    xvfb-run WITHOUT --headless, with --rendering-driver opengl3, driven by
#    an `extends SceneTree` script that instantiates the scene, waits a few
#    process_frame, then root.get_texture().get_image().save_png(...).
```

### Working rules

1. **Never break the smoke test.** Run it after every task. Every bug fixed
   below gets a regression assert added to `_smoketest.gd`.
2. **One phase = one coherent commit series.** French commit messages,
   imperative mood, matching the existing history.
3. **Update the docs you invalidate** (`README.md`, `RESUME_SESSION.md`).
4. Work through phases in order; within a phase, tasks are dependency-ordered.
5. Balance numbers live in `Data.gd` (data-driven, tunable), never inline.
6. No new third-party dependencies. Don't rewrite systems that work.
7. When this guide's line references have drifted (they anchor to the state
   at commit `24ecda3`), locate by function name — every reference includes
   one.

---

## PHASE 1 — Bug fixes (confirmed defects; small, high value)

### 1.1 Floor off-by-one
**Defect**: `start_run()` sets `floor_num = 1` (Main.gd:222), then
`_advance("combat")` executes the default match branch which does
`floor_num += 1` (Main.gd:354) → first playable floor displays « Étage 2 ».

**Fix**: initialize `floor_num = 0` in `start_run()`. Nothing else — the
increment site is correct.

**Ripple check** (verify, no change expected): `Data.biome_for_floor` clamps
via `max(1, floor)`; `_pick_enemy_def` min_floor gating, item scaling
(`Data.generate_item`), knowledge gain (`floor_num - GameState.best_floor`,
Main.gd:2107) all consume the now-correct value. Note the knowledge economy
tightens by 1 for record-breaking runs — intended.

**Assert**: after `start_run("melee")`, `main.floor_num == 1`.

### 1.2 Boss power drop is dead code
**Defect**: `on_enemy_killed` → `if floor_num % 15 == 0: _drop_power(...)`
(Main.gd:1305). Boss floors are ≡ 1 (mod 6); `6k+1 ≡ 0 (mod 15)` has no
solution — never fires.

**Fix**: `run_bosses` is incremented 6 lines above (Main.gd:1299). Replace
the condition with `if run_bosses % 2 == 0:` → a guaranteed power on every
2nd Guardian (bosses #2, #4, #6…). *(cadence: tune)*

**Assert**: set `run_bosses = 1`, kill a spawned boss via
`on_enemy_killed`, assert a loot entry with `kind == "power"` exists.

### 1.3 `weaken` has no effect on enemies (Représailles prefix is a no-op)
**Defect**: only `_player_def()` (Main.gd:1077) reads the `weaken` status.
`_enemy_atk(e)` (Main.gd:1706) ignores it, so the armor prefix `renvoi`
(Main.gd:1252) applies a status nothing reads.

**Fix** in `_enemy_atk`, after the pack bonus:
```gdscript
if e.has_status("weaken"):
    a -= int(round(e.status_value("weaken")))
return maxi(1, a)
```
Covers all paths: melee, ranged (`_enemy_ranged_attack`), and charger
(charger multiplies `e.atk` before calling `_enemy_attack_player`, which
routes through `_enemy_atk` — verified).

**Assert**: apply `apply_weaken(enemy, 3, 3.0)`, assert
`main._enemy_atk(enemy) == maxi(1, enemy.atk - 3)`.

### 1.4 Boss shield-guardians spawn anywhere / linger after boss death
**Defect A**: `_boss_on_spawn` places guardians via
`dungeon.random_floor_tiles(count, rng, occupied)` — anywhere on the map
(Main.gd:534). With `resist` 0.85-0.9 the boss is near-immortal until the
player finds them, potentially hundreds of tiles away in fog.

**Fix A**: add to `Dungeon`:
```gdscript
func random_floor_tiles_near(center: Vector2i, radius: int, count: int,
        rng: RandomNumberGenerator, exclude: Array) -> Array
```
Filter `reachable_tiles` by Chebyshev distance ≤ radius (build the filtered
list once, then sample like `random_floor_tiles`). Call it with
`radius = 6` from `_boss_on_spawn`; if it returns fewer than `count`, top up
from the global sampler (degenerate tiny-arena case).

**Defect B**: when the boss dies, its `stationary` 0-ATK guardians remain as
inert husks.

**Fix B**: in `on_enemy_killed`, inside the `if e.is_boss:` branch, before
the reward logic:
```gdscript
for g in enemies.duplicate():
    if int(g.ai.get("guard_for", 0)) == e.get_instance_id():
        if map_view != null: map_view.fx_death(g)
        enemies.erase(g)
```
Dissolve silently (no shards/XP — do NOT route through `on_enemy_killed`,
that would recurse and pay the player), plus one log message
(« Les gardiens se dissipent avec leur maître. »). **Trap**: iterate over
`enemies.duplicate()` since you erase while iterating.

**Assert**: spawn the Seigneur Fantôme via `_make_enemy` +
`_boss_on_spawn`; assert every guardian within Chebyshev 6 of the boss;
kill the boss; assert no entity with `guard_for` remains.

### 1.5 Uncapped dodge / crit / lifesteal
**Defect**: `Entity.recompute_stats` (Entity.gd:240-255) never clamps.
Voile d'Ombre (+20 % dodge) + the repeatable Agilité talent (+10 % each) +
affixes reach 100 % dodge → immortality.

**Fix**: constants in `Data.gd`:
```gdscript
const CAP_DODGE := 0.60
const CAP_CRIT := 0.75
const CAP_LIFESTEAL := 0.50
```
Clamp in `recompute_stats` next to the existing `speed = max(20, speed)`
floor: `dodge_chance = minf(dodge_chance, Data.CAP_DODGE)` etc. Harmless for
enemies (they never set these stats).

**Assert**: stack three `{"mods": {"dodge_chance": 0.30}}` talents, recompute,
assert `dodge_chance == 0.60`.

### 1.6 Forge amplifies maluses
**Defect**: `forge_choice` (Main.gd:2076-2082) boosts each bonus by ±30 %
respecting the sign (`signi(int(v))`) — `speed: -5` becomes `-7`.

**Fix**: in both branches skip non-positive values (`int(v) <= 0` /
`float(v) <= 0.0` → `continue`). The existing `boosted` flag then correctly
falls through to the `bonus["atk"] += 2` consolation for all-malus items.

**Assert**: forge an item with `{"atk": 4, "speed": -5}`; assert speed still
−5 and atk > 4.

### 1.7 Layout-dependent input (WASD broken on AZERTY)
**Defect**: `_unhandled_input` matches `event.keycode` (Main.gd:731) —
layout-dependent, and nothing is rebindable.

**Fix**: define actions in `project.godot` `[input]` (preferred over code so
users can edit): `move_up`, `move_down`, `move_left`, `move_right`, `wait`,
`ability`, `inventory`, `cancel`. Each movement action binds the
**`physical_keycode`** of W/A/S/D **plus** the arrows **plus** H/J/K/L
(physical); `wait` = `.` and KP5; `ability` = Space and E; `inventory` = I;
`cancel` = Escape. Rewrite `_unhandled_input` matches as
`event.is_action_pressed("move_up")` etc. (default `allow_echo=false`
preserves the current echo filtering). Movement handling moves to polling in
Phase 3.4 — for now a straight translation is fine.

**Verify**: in-game (xvfb) the physical WASD positions move Aria regardless
of layout; smoke test unaffected (it calls `try_move` directly).

### 1.8 No pause / no way to quit a run
**Fix**:
- Add `State.PAUSED` to the enum (Main.gd:6).
- In `_unhandled_input`, `cancel` while `PLAYING` → `open_pause()`
  (state = PAUSED, `hud.show_pause()`); `cancel` while PAUSED → resume.
- `Hud.show_pause()`: overlay with **Reprendre** (`game.close_pause`),
  **Options** (`show_options` — it already renders over the overlay layer),
  **Abandonner l'ascension** (`game.abandon_run`).
- Refactor: change `game_over()` → `game_over(abandoned := false)`. When
  abandoned: shard banking multiplier ×0.75 *(tune)* applied before
  `oath_shard_mult()`, summary text « Tu renonces à l'Étage %d. », and the
  same `record_run` path (an abandoned floor still counts for records —
  the player genuinely reached it).

**Assert**: `abandon_run()` from PLAYING banks
`int(round(run_shards * 0.75 * oath_shard_mult()))` and lands in GAMEOVER.

### 1.9 UI breaks off 16:9
**Defect**: `stretch/aspect="expand"` (project.godot:23) resizes the
viewport with window aspect, but the HUD is absolutely positioned against
`VIEW = 1280×720` (Hud.gd:7, sidebar panel Hud.gd:79, log Hud.gd:191, hub
button Hud.gd:304; TownView.gd:11).

**Fix** (option a — anchors):
- Sidebar panel: `set_anchors_preset(PRESET_RIGHT_WIDE)`,
  `custom_minimum_size.x = SIDEBAR_W`, `offset_left = -SIDEBAR_W`.
- Log panel: `PRESET_BOTTOM_WIDE`, height `LOG_H - 10`,
  `offset_right = -SIDEBAR_W - 12` (log spans the play area only).
- Hub back button: `PRESET_TOP_RIGHT` with offsets.
- `Hud.play_area()` returns
  `get_viewport().get_visible_rect().size - Vector2(SIDEBAR_W, LOG_H)`.
- `Main._ready`: connect `get_viewport().size_changed` →
  `map_view.view_size = hud.play_area()`; `refresh()` (re-centers camera).
- **Trap**: `MapView._vignette_tex` is cached at the first `view_size`
  (MapView.gd:281) — set it to `null` in the resize handler so it
  regenerates at the new size.
- `TownView._draw`: replace the `VIEW` constant with
  `get_viewport_rect().size` at draw time.

**Verify**: xvfb screenshots at 1280×720, 1024×768, 2560×1080 — sidebar hugs
the right edge, log hugs the bottom, town stays centered.

### 1.10 Oath of Poverty leaks a starting bonus
**Defect**: « aucun bonus de départ », but the Knowledge node
`Pacte de Pouvoir` still grants its starting power (Main.gd:256 —
`starts_with_power()` sits outside the `if not has_oath("pauvrete")` guard).

**Fix**: move that block inside the guard.

**Assert**: with `knowledge_nodes = ["pacte_pouvoir"]` and the oath active,
`start_run` yields `player.powers.is_empty()`.

**Phase 1 done when**: all 10 fixed, smoke test green with the new asserts,
and README corrected where it lies: sprites are 32×32 not 24×24
(README.md:142); Guardian cadence is every 6 real floors, not 5
(README.md:12) — fix the text (do NOT change `ACT_LENGTH` semantics).

---

## PHASE 2 — Combat fairness (the felt-quality core)

### 2.1 Shared line-of-sight
**New primitive** in `Dungeon`:
```gdscript
func has_los(a: Vector2i, b: Vector2i) -> bool
```
Standard Bresenham (copy the integer form from `_assets_gen.gd::_line`) from
`a` to `b`, testing every intermediate cell (exclusive of both endpoints):
blocked if `tiles[y][x]` is WALL, TREE or ROCK. **WATER does not block
sight.** Bresenham is not symmetric between octants — that's acceptable;
adopt the convention that every check is written `has_los(attacker, target)`
so a given shot is at least self-consistent.

**Apply to the player side** — `_nearest_enemy_in_range` (Main.gd:959) gains
three filters:
```gdscript
if not dungeon.is_visible(e.x, e.y): continue        # fog
if e.ai.get("behavior", "") == "ambush" and not e.revealed: continue  # mimic
if not dungeon.has_los(player.pos(), e.pos()): continue
```
The mimic filter matters: auto-aim currently *detects* disguised mimics.
Same filters in `_nearest_enemy_excluding` (bounce chains) — **except** LoS
between chain hops is deliberately waived (it's arcing magic); visibility of
the hop target is still required. `aoe_attack` (Main.gd:973): require
`has_los(center, e.pos())` only when `radius >= 2` (radius-1 bursts always
hit — walls don't matter at point-blank and it keeps Tourbillon d'acier
reliable). `pierce_attack` already walks tiles and stops on obstacles —
correct as is. Drone/turret (`_trigger_powers`) route through
`_nearest_enemy_in_range` — fixed for free.

**Apply to the enemy side** — `_enemy_act_ranged` (Main.gd:1766) and
`_enemy_act_caster`'s scream path: shooting/screaming at the player requires
`dungeon.is_visible(e.x, e.y)` (if the player can't see the enemy, the enemy
holds fire — vision is radius-based and symmetric, so this is exactly « pas
de tir depuis le néant ») **and** `dungeon.has_los(e.pos(), player.pos())`.
When the shot is blocked, fall through to the existing approach/kite
movement. Summoning does not require visibility (reinforcements arriving
from darkness is fine and flavorful).

**Assert**: build a 9×9 `Dungeon`, force a ROCK line between a ranged enemy
and the player, run `_enemy_act(e)` — player HP unchanged; mirror-check
`_nearest_enemy_in_range` returns null through the same wall.

### 2.2 Vision vs enemy range
`BASE_VISION := 4` (Data.gd:106) vs enemy ranges up to 7 (Œil du Néant).
With 2.1 an unseen enemy can no longer fire, but a range-7 enemy would sit
permanently outside a radius-4 view and never act. Set `BASE_VISION := 6`
*(tune)*. The torch-pool overlay radius derives from `player.vision`
(MapView.gd:292) — scales automatically.

### 2.3 Aggro radius (kill the omniscient AI)
- `Entity`: add `var awake := false`.
- Top of `_enemy_act(e)` (Main.gd:1628), before ANY passive trait
  (disease aura, copy_player, traps — they must not run while dormant):
```gdscript
if not e.awake:
    if e.is_boss or String(e.ai.get("behavior", "")) == "stationary": e.awake = true
    elif e.hp < e.max_hp: e.awake = true                    # took damage
    elif dungeon.is_visible(e.x, e.y): e.awake = true       # seen (mutual)
    elif _chebyshev(e.pos(), player.pos()) <= int(e.ai.get("aggro", 8)): e.awake = true
    if e.awake and String(e.ai.get("behavior", "")) != "ambush":
        for o in enemies:                                    # shout
            if o.is_alive() and not o.awake and _chebyshev(e.pos(), o.pos()) <= 4:
                o.awake = true
    else:
        return                                               # still dormant: skip turn
```
**Traps**: mimics (`ambush`) must never shout or be woken by shouts —
their behavior function already self-gates on adjacency, but gate the shout
both ways so a woken wolf doesn't out a mimic. Dormant enemies still accrue
energy in `advance_world` — harmless, they just skip acting. Summoned/spawned
enemies (`_enemy_summon`, `spawn_on_hit`): set `awake = true` at creation.

**Assert**: on a large forced map, a melee enemy 30 tiles away stays at its
position after 5 player waits.

### 2.4 Minimal obstacle avoidance
Two tiers:
- **Everyone**: extend `_enemy_step_toward` (Main.gd:1668) — after the two
  greedy tries fail, try the two perpendicular directions in rng order (4
  candidates total). One line of behavior, unsticks most terrain.
- **Bosses & elites** (`e.ai["smart_path"] = true`, set in `generate_floor`
  for `is_boss` and elite-buffed enemies): add
  `Dungeon.next_step(from: Vector2i, to: Vector2i, max_nodes := 400) -> Vector2i`
  — A* (4-connected, Manhattan heuristic, other entities treated as free —
  collision already resolves at move time) that aborts at `max_nodes`
  expansions and returns `NO_TILE`/from on failure; caller falls back to the
  greedy step. Called at most once per smart entity per turn — a handful per
  floor, no caching needed.

**Assert**: hand-built map with a 5-tile water pond between boss and player;
boss reaches adjacency within 25 turns of `pass_turn()`.

### 2.5 Telegraphed enemy intents
Single source of truth (this must NOT re-implement the AI — it inspects the
same fields the behaviors read):
```gdscript
func enemy_intent(e: Entity) -> String   # in Main (EnemyAI after 7.3)
```
Returns, in priority order: `""` for unrevealed mimics (never leak);
`"sleep"` if `not e.awake`; `"attack"` if `_manhattan == 1`;
`"charge"` if behavior charger and orthogonally aligned with clear lane;
`"shoot"` if behavior ranged and dist ≤ ranged_range and `ai_cd <= 0` and
LoS; `"cast"`/`"summon"` for casters with cooldown ready in range;
`"flee"` for fleers under their HP threshold; else `"approach"`.

`MapView`: for each visible enemy, draw a 10 px backing rect
(INK, alpha 0.6) at the cell's top-right corner + a glyph via `_draw_glyph`
at font size 10: 💤→`z`, attack→`!`, shoot→`↣`, charge→`»`, cast/summon→`✦`,
flee→`…` *(replaced by generated icons in Phase 8.A.6 — use ASCII-safe
glyphs now, not emoji)*. Colors: red for attack/charge, orange shoot, violet
cast, grey sleep/flee.

**Assert**: intent of an adjacent melee enemy is `"attack"`; of a dormant
one `"sleep"`; of an unrevealed mimic `""`.

### 2.6 Turn-order strip (make the energy system visible)
Pure simulation in Main:
```gdscript
func preview_turn_order(n := 8) -> Array   # of Entity refs
```
Copy `(entity, energy, effective_speed())` into local dicts for the player +
awake living enemies. Loop: for each, `ticks_to_ready =
ceili((ACTION_COST - energy) / float(speed))`; the minimum acts next
(ties: player first, then array order); advance all energies by
`min_ticks * speed`, subtract `ACTION_COST` from the actor, append it;
repeat until `n` entries. **Must not touch real entities.**

Hud: a horizontal strip above the log (fits in the existing free margin):
`n` 26×26 panels — mini sprite (`TextureRect`, lazy-load
`res://assets/%s.png`, nearest filter; fallback: glyph label in the entity's
color), player's panel border in ACCENT. Rebuild inside `refresh()`
only when the computed order changed (cache an Array of instance ids).

**Assert**: with player speed 100 and one enemy speed 200, preview begins
`[player, enemy, enemy, player]` (player has the energy head start from
`generate_floor`).

### 2.7 Enemy inspection
- **Hover**: `MapView` gets `func tile_at_mouse() -> Vector2i` =
  `floor(get_local_mouse_position() / CELL)` (local coords already include
  the camera offset since `position` is the camera). In `_process`, when the
  hovered tile holds a visible living enemy (skip unrevealed mimics), call
  `hud.show_inspect(e)`; else `hud.show_inspect(null)`.
- **Hud**: new sidebar section `INSPECTION` (between ÉTATS and ÉQUIPEMENT)
  filled on demand: name; `PV x / y`; `ATK n` (+ « (meute) » when
  `ai.pack`); `VIT n`; behavior label from a FR table
  (`melee→Corps à corps, ranged→Tireur, caster→Invocateur/Hurleuse,
  charger→Chargeur, fleer→Fuyard, teleporter→Insaisissable`); on-hit status
  (« Au contact : Poison (3 t) »); resist lines (« Résiste au physique
  60 % » / « Vulnérable à la magie » for negative values; « Craint le feu »
  for weak_fire; « Insensible au feu »). All read straight from `e` and
  `e.ai` — no new data.
- Keyboard parity can wait; note it as a TODO in code.

**Phase 2 done when**: all six in, smoke test green, and one xvfb screenshot
shows intents + turn strip + inspection panel simultaneously.

---

## PHASE 3 — Feel & polish pass (the “real game” signals)

### 3.1 Pixel font
Two acceptable routes — try A, fall back to B:
- **A (preferred)**: vendor a CC0 pixel TTF (e.g. *monogram* — CC0; check
  the license file into `assets/fonts/` alongside it). Verify French
  diacritics (é è ê à ç ù ô î ï œ « » −) render — this is the gate; a font
  missing them is disqualified.
- **B (if network policy blocks downloads, or diacritics fail)**: generate a
  BMFont from code: `_assets_gen.gd` renders a 6×9 glyph grid atlas PNG
  (ASCII 32-126 + the accented set above) and writes the matching `.fnt`
  descriptor; Godot 4 loads BMFont natively. More work, fully on-brand
  (everything generated).

Integration: build one `Theme` in `Ui.gd` (`static func theme()`) — default
font + default font size 16 — and assign `get_window().theme` in
`Main._ready`. Existing per-label `font_size` overrides keep working; audit
sizes so they land on multiples that keep the bitmap crisp (16/32; the
current 10-13 px micro-labels move to the font's native small size).
**Trap**: `MapView`/`TownView` draw text via `ThemeDB.fallback_font`
(`_font` members) — point them to the new font resource explicitly.

### 3.2 Sound
- **Generation** (`_sfx_gen.gd`, SceneTree script, same pattern as the asset
  generator): synthesize PCM16 mono 22 050 Hz into `AudioStreamWAV`
  (`format = FORMAT_16_BITS`, set `data`), `save_to_wav("res://assets/sfx/<id>.wav")`.
  Ten recipes *(all tune)*:
  `hit` 60 ms white-noise burst, exponential decay, mixed with a 150 Hz sine
  thump; `crit` = hit + square chirp 400→900 Hz 80 ms; `kill` saw sweep
  300→80 Hz 150 ms; `pickup` two square blips 660/990 Hz 40 ms;
  `levelup` square arpeggio 523/659/784 Hz 60 ms each; `stairs` filtered
  noise swell 200 ms; `buy` sine 1320 Hz with fast decay ×2; `heal` sine
  swell 440→660 Hz 250 ms; `ui` 10 ms square tick; `danger` two 110 Hz
  square pulses. Normalize peaks to −6 dBFS.
- **Playback**: new autoload `Sfx` (register in project.godot): pool of 8
  `AudioStreamPlayer`s, `Sfx.play(id: String, vol_db := 0.0)` — lazy-load
  streams, round-robin the first idle player, apply master SFX volume.
  Headless-safe by construction (playing into a null device doesn't crash;
  still guard `ResourceLoader.exists`).
- **Hooks**: `_player_attack` (hit/crit), `on_enemy_killed` (kill; danger on
  boss), `_bag_add`/`_pickup_loot_at` (pickup), `_check_level_up` (levelup),
  `_node_cleared` (stairs), `buy_shop_item`/`buy_shop_heal` (buy),
  `use_consumable` heal effects (heal), `Ui._style_button` — connect each
  button's `pressed` to `Sfx.play("ui")` centrally in `Ui.button()`.
- **Settings**: `GameState` gains `settings := {"sfx_vol": 0.8,
  "music_vol": 0.8, "screenshake": true}`, persisted in the save (see 7.2);
  Options screen gets two `HSlider`s + the shake toggle.

### 3.3 Movement & combat juice (all inside MapView; logic stays instant)
- **Tweened movement**: `_vis_pos: Dictionary` (instance_id → Vector2
  pixels). Each `_process`:
  `vp = vp.lerp(logical_px, minf(1.0, delta * 14.0))` *(≈80 ms; tune)*;
  entities draw at `_vis_pos` instead of the cell rect (extend
  `_blit_ex_off` to take an absolute px position). Initialize on first
  sight; snap (no tween) when the entity was previously invisible —
  otherwise off-screen spawns slide across the map.
- **Floating damage numbers**: `_floaters: Array` of
  `{text, color, px, t}`; `fx_damage(pos: Vector2i, amount: int, kind)`
  with kinds `hit` (white 12 px) / `crit` (gold 16 px) / `player_hit`
  (red) / `heal` (green, "+n"); rise 14 px over 0.6 s, alpha fade, drawn
  after entities. Hooks in Main: `_player_attack` (after `dealt`),
  `_enemy_hit_player`, `_trigger_weapon_prefixes`, DoT tick in
  `_begin_turn`, the lifesteal/potion/rest heal sites.
- **Hit-stop**: `_freeze_until: float`; on player crit set
  `_anim_t`-freeze for 0.05 s (skip advancing `_anim_t` and `_vis_pos`
  lerps while frozen). Do NOT touch `Engine.time_scale`.
- **Screenshake**: Main writes `map_view.base_position` (rename in
  `_update_camera`); MapView applies
  `position = base_position + Vector2(rng ±_shake_mag)` in `_process`,
  `_shake_mag` decaying ×0.85/frame. `fx_shake(4.0)` on player crit and
  boss rage. Respect `GameState.settings.screenshake`.

### 3.4 Input responsiveness
- Movement moves from `_unhandled_input` to polling in `Main._process`
  (PLAYING only): on `is_action_just_pressed` act immediately and set
  `_repeat_at = now + 0.25`; while held and `now >= _repeat_at`, act and set
  `_repeat_at = now + 0.09` *(tune)*. Remove the four movement cases from
  `_unhandled_input` (keep wait/ability/inventory/cancel there).
  Hub movement (`_hub_try_move`) gets the same treatment.
- **Overlay keyboard nav**: every overlay builder in Hud
  (`show_floor_reward`, `show_event`, `show_rest`, `show_levelup`,
  `show_forge`, `show_pause`, shop) calls `grab_focus()` on its first
  button. Godot's built-in focus chain (arrows/Tab) plus Enter-to-press
  then works with zero extra code. Ui buttons keep default `FOCUS_ALL`.

### 3.5 Ambient particles per biome (draw-based, no scene nodes)
- `Data.BIOMES[*]` gains
  `"ambient": {"color": Color, "count": int, "vel": Vector2, "size": int}`:
  plaine = pollen (gold, drift up-right, 18), forêt = leaves (green,
  down-drift, 24), désert = dust (bone, fast horizontal, 16), toundra =
  snow (white, slow down, 40), marais = fireflies (poison green, sinusoidal
  hover, 14), volcan = ash/embers (ember, rise, 22).
- MapView `_process`: maintain `_motes: Array` of `{px, phase}` in
  **view-space**; advance by `vel * delta` (+ `sin(phase + _anim_t)` sway
  for fireflies), wrap around `view_size`; draw as 1-2 px rects at
  `origin + px` after atmosphere, alpha ~0.5. Rebuild the pool when
  `dungeon.biome` changes. Skip when `dungeon == null`.

### 3.6 Death recap
- Main: `var last_damage_source := ""` — set at every
  `player.take_damage` site: enemy display_name (melee/ranged/explosions),
  « un piège », « les toxines » (DoT in `_begin_turn`), event names.
- `game_over` adds `stats["killed_by"] = last_damage_source`;
  `Hud.show_gameover`/`_build_run_journal` renders « Terrassée par %s » and,
  when `0 < best_floor - floor <= 3`, « À %d étage(s) de ton record. ».
- Run timeline: `run_timeline: Array` — push entries at biome entry
  (« Étage %d — %s »), boss kills, power pickups; cap 40; render the last
  10 as a compact list in the game-over column.

### 3.7 Log & seeds
- `MAX_LOG` 8 → 200 (Main.gd:8). Hud log: `scroll_active = true`,
  `fit_content = false`, after assignment call
  `log_label.scroll_to_line(log_label.get_line_count() - 1)`. Visual panel
  size unchanged; wheel scrolls history.
- **Seeded runs**: `start_run(loadout_id, forced_seed := -1)`: if −1,
  `rng.randomize()` then read back `run_seed = rng.seed`; else
  `rng.seed = forced_seed`. Display the seed in the game-over journal and
  the pause menu (copyable via log message).
- **Unify RNG**: the one non-`Main.rng` gameplay roll is
  `pool.shuffle()` in `Hud.show_levelup` (Hud.gd:830) — replace with a
  3-pick using `game.rng.randi_range` without replacement (and move the
  pick into Main so Hud stays logic-free: `game.roll_talent_choices()`).
  Grep for `randi(`/`randf(`/`shuffle(` outside `Main.rng`/generators to
  confirm nothing else leaks.

**Assert**: two `start_run("melee", 12345)` calls produce identical
`dungeon.start`, `dungeon.stairs`, enemy count and first-enemy position.

**Phase 3 done when**: all seven in, smoke test green (incl. the seed
assert), README « Interface »/« Contrôles » updated (pause, scrolling log).

---

## PHASE 4 — The hook: elemental terrain (vertical slice first)

Rationale: VISION.md §2.A. **Build the Forêt fire slice first, validate fun,
then extend.** All randomness through `Main.rng`.

### 4.0 Substrate: the effects layer
- `Dungeon` gains:
  - `var effects: Array` (grid of int: `EFF_NONE/EFF_BURNING/EFF_BURNT/
    EFF_FROZEN/EFF_CLOUD`), `var effect_timer: Array` (grid of int),
    `var active_effects: Array[Vector2i]` — **iterate this list, never the
    full grid** (640×400 exists).
  - `is_walkable` change: FROZEN water is walkable
    (`t == WATER and effects == EFF_FROZEN → true`); BURNT is just FLOOR
    (the tile itself is rewritten, see below).
  - `func rebuild_reachability()` — re-runs `_reachable_set` +
    `reachable_tiles` cache; call after any tile mutation (burnt tree,
    freeze, melt). **Trap**: the cache exists (Dungeon.gd:80) and silently
    goes stale otherwise.
- Main: `func _tick_terrain()` called once per player action, at the top of
  `_player_acted` (terrain moves at player cadence, before enemies act).

### 4.1 Vertical slice — fire spreads in the Forêt
- `func ignite(p: Vector2i) -> bool` (Main): if `tiles[p] == TREE` and
  effect is NONE → set BURNING, timer 4, append to `active_effects`,
  message + `Sfx.play("danger")` first time per floor.
- Ignition sources (hook exactly these):
  - skills with `"status": "burn"` (`ember`, `fireball`'s explosion): after
    resolving, attempt `ignite` on every TREE within the blast radius /
    adjacent to the struck target;
  - the `ardent` weapon prefix: 25 % *(tune)* per hit to ignite one TREE
    adjacent to the target;
  - Élémentaire de feu death explosion and cultist sacrifice: ignite TREEs
    in radius;
  - burning entities do NOT ignite terrain (v1 — keeps chains readable).
- `_tick_terrain()` per BURNING cell:
  1. `timer -= 1`;
  2. damage: every entity (player included!) in the 8-neighborhood gets
     `apply_burn(ent, 2, 2.0 + floor_num * 0.2, 3)`;
  3. spread: each 4-neighbor that is TREE with EFF_NONE → 35 % *(tune)*
     becomes BURNING (timer 4);
  4. at timer 0: effect = EFF_BURNT, `tiles[p] = FLOOR`, `decor[p] = ""`,
     mark a burnt-ground flag MapView can render (dark scorch overlay; a
     dedicated sprite arrives with Phase 8), and set a
     `_reach_dirty = true` flag — call `rebuild_reachability()` once at the
     end of the tick, not per cell.
- Fog discipline: burning/burnt render only on explored tiles, full color
  only in vision — same rules as everything else. Fire keeps ticking in the
  fog (you hear about it only when you see it).

**Assert (scripted)**: build a small Dungeon by hand (fill FLOOR, plant a
5-TREE row, `rebuild_reachability`), `ignite` one end, run `_tick_terrain`
×12 with spread chance forced to 1.0 (expose the chance as a `Data`
constant so the test can set it): all 5 trees end BURNT and walkable; an
entity parked adjacent accumulated burn stacks.

**→ STOP. Play it (xvfb + manual run), screenshot a burning forest, decide
it's fun. Only then continue.**

### 4.2 Extensions (each = same pattern: rule, hooks, scripted assert)
- **Element tags**: add `"elem"` to `Data.SKILLS` entries — `bolt`,
  `arc_bolt`, `chain_lightning` = `"lightning"`; `fireball`, `ember` =
  `"fire"`; `frost_nova`, and the `givre` prefix = `"frost"`.
- **Water conducts lightning**: entities never stand IN water (unwalkable) —
  the rule is **adjacency**: when a lightning skill damages a target that is
  4-adjacent to a WATER cell, flood-fill that water body (cap 500 cells,
  cache per cast) and deal 50 % of the hit to every OTHER enemy 4-adjacent
  to the body. Message + a crackle along the shoreline (reuse fx_hit on
  targets).
- **Frost freezes water**: a frost skill striking a target adjacent to
  water (or `frost_nova` centered near it) sets EFF_FROZEN on the connected
  water cells within radius 4 of the impact, timer 10 player-turns →
  reverts. Walkable while frozen (`is_walkable` above +
  `rebuild_reachability`). On melt with an entity standing on it: relocate
  to nearest walkable tile, 3 damage, slow 2 (« la glace cède ! »). Fire
  (any) on a FROZEN cell melts it instantly.
- **Poison clouds (marais)**: serpents and zombies leave, on death (30 %),
  EFF_CLOUD radius 1, timer 3; entities inside get
  `apply_poison(ent, 2, 3.0)` per tick. Render: translucent poison-green
  circles.
- **Lava (volcan)**: volcan's WATER is lava. No passive adjacency damage
  (too punishing). Being **pushed into** lava (4.3): 8 + floor damage +
  burn 3, entity stays on its origin tile (bounced back).

### 4.3 Knockback (multiplies every rule above)
```gdscript
func push_entity(target: Entity, dir: Vector2i, tiles: int) -> void
```
Per step: `next = pos + dir` —
walkable & free → move; occupied by enemy → both take 2, stop;
WATER (volcan) → lava rule above, stop; WATER (elsewhere) → 3 dmg + slow 2,
stop (stays on last valid tile); FROZEN → slides (continue 1 extra step);
BURNING-adjacent destination → burn applies via the normal tick; hazard
tile → trigger it against the pushed enemy (extend `_trigger_hazard_at`
with an entity parameter — traps finally cut both ways).
Sources: new commune melee skill `shield_bash` « Coup de bélier »
(cd 3, power 0.8, push 2); the charger behavior pushes 1 on hit; the
Bourreau pushes 2.

**Phase 4 done when**: slice + ≥2 extensions + knockback shipped, each with
a scripted assert; skill/prefix descriptions updated to mention terrain;
VISION.md updated with what was validated/cut.

---

## PHASE 5 — Balance instrumentation & tuning

### 5.1 Autoplay harness (`_balance_sim.gd`, SceneTree script)
- Instantiate `Main.tscn` like the smoke test. Policy per state:
  - PLAYING: drink a heal consumable if `hp < 35 %`; `use_ability()` if
    ready and a visible enemy is in range; else step via
    `dungeon.next_step(player.pos(), target)` toward nearest visible enemy,
    else toward `dungeon.stairs` (2.4's A* reused — this is why it lives in
    Dungeon).
  - CHOICE floor reward: equip if `_rarity_rank` beats the current slot
    item, else heal if `hp < 60 %`, else shards. Shop: buy heal if
    `hp < 50 %` and affordable, else leave. Event: choice 0. Rest: heal.
  - LEVELUP: `pick_talent` first offer. INVENTORY: never opens.
  - Safety: hard cap 20 000 actions per run, then record as `"stalled"`.
- Runs: `OS.get_environment("SIM_RUNS")`, default 50 (GDScript on 640×400
  maps is slow — expect minutes; that IS the measurement).
- Output `user://balance_sim.csv`:
  `seed,death_floor,killed_by,level,kills,turns,shards_banked,best_rarity,stalled`
  + print p25/p50/p75 of death_floor at the end.

### 5.2 Tune with data (targets; all knobs in Data.gd)
- Target: median no-meta death floor ≈ **12-15**. Levers, in order:
  enemy scale slope (`_make_enemy`, Main.gd:593 — currently
  `1 + 0.12/floor` on HP **and** ATK; split the two slopes), **scale enemy
  defense** (currently unscaled, Main.gd:603 — add ×`1 + 0.06/floor`),
  item scale slope (Data.gd:628, `1 + 0.08/floor`).
- **Decouple XP from shards**: `Entity` gains `xp_value`; `_make_enemy`
  sets it from `def.get("xp", def["shards"])` (add explicit `"xp"` to each
  ENEMIES/BOSSES entry, starting equal to shards); `on_enemy_killed` uses
  it. Curve: `xp_to_next(level) = 10 + level * level * 3` *(tune)* —
  kills the early level flood.
- Gamble event becomes a gamble: 55 % → +25 shards, 45 % → lose 15 % max HP
  *(tune)*.
- Enemy pool weighting: ENEMIES entries gain optional `"max_floor"`;
  `_pick_enemy_def` filters on it (gobelin/kobold out past ~14 — let weak
  species retire instead of scaling forever).
- Commit the before/after CSVs under `docs/balance/` with a dated note.

---

## PHASE 6 — Content depth (only after Phase 5 exists)

### 6.1 Mechanical talents (replace ≥8 flat +stat entries)
Talents gain an optional `"hook": String` consumed at explicit sites
(`player.has_talent_hook(id)` helper on Entity scanning `talents`):
| id | Effect | Hook site |
|---|---|---|
| `pyromane` | tes ignitions se propagent à 50 % (au lieu de 35 %) et brûlures +1 stack max | `_tick_terrain` spread roll; `apply_burn` cap |
| `balistique` | +1 rebond et +2 de portée de transpercement | `_cast_skill` bounce/pierce params |
| `toxicologue` | tes poisons ont une valeur ×1.6 | `apply_poison` (player-sourced calls only — statuses don't track their applier; this is the honest v1) |
| `echo_arcanique` | 15 % de chances de ne pas consommer la recharge | `use_ability` after cast |
| `pied_leger` | les pièges ne se déclenchent plus sous tes pas et sont visibles hors vision | `_trigger_hazard_at`; MapView hazard draw |
| `berserker` | +25 % dégâts tant que tu subis un DoT | `_player_attack` raw calc |
| `chasseur_nuit` | +2 Vision et +10 % dégâts à distance ≥ 4 | mods + `_player_attack` |
| `demolisseur` | tes poussées gagnent +1 case et infligent +3 | `push_entity` |

### 6.2 Elite affixes (replaces the flat ×1.25 sponge, Main.gd:472-476)
One affix rolled per elite; name becomes « Élite %s : %s ». `Entity` gains
`var tint := Color.WHITE`; MapView passes it as the `modulate` argument of
`draw_texture_rect` in the entity pass.
| id | Effect | Data | tint |
|---|---|---|---|
| rapide | +40 speed | stat | cyan |
| explosif | explodes on death | reuse `ai.explode` | orange |
| regenerant | hp_regen 4 | stat | green |
| voleur | steals 4 shards per hit, returns all on its death | new ai flag, hooks in `_enemy_hit_player`/`on_enemy_killed` | gold |
| chef | +2 ATK aura to allies within 3 | fold into `_enemy_atk` (scan for a live `chef` nearby) | red |
Keep a reduced stat bump (+15 % HP) on top.

### 6.3 Pool expansion
Artifacts 5 → ~15, powers 5 → ~12, events 7 → ~20 (at least one per biome,
gated by `dungeon.biome.id`… events fire between floors — gate on the
*upcoming* floor's biome), consumables 4 → ~10 (bombe = aoe 2 at a thrown
visible tile; antidote = clear DoT statuses; parchemin de rappel = teleport
to stairs-adjacent explored tile; huiles d'arme = temp element on hits for
20 turns, feeding Phase 4). Follow the existing dict schemas exactly.

### 6.4 Merge artifacts + powers into « Reliques » (requires 7.2 first)
- One registry `Data.RELICS` = ARTIFACTS ∪ POWERS entries with a
  `"tier"` field; one `player.relics` list; `ARTIFACT_MODS`/`POWER_MODS`
  merge into `RELIC_MODS`. Keep thin compat wrappers
  (`has_artifact`/`has_power` delegating) during the change, delete at the
  end. Hud: one sidebar section. Codex: migrate `discovered["power"]` +
  `discovered["unique"]`-adjacent artifact keys into `"relic"` in the save
  migration (7.2). Exclusions (`excludes`) carry over unchanged.

### 6.5 Bestiary in the Codex
- `GameState`: `discovered["monster"]` + `kill_counts: Dictionary`
  (sprite id → int, persisted). `on_enemy_killed`: increment +
  `note_discovery("monster", e.sprite)` (name revealed at first kill;
  traits line shown at ≥5 kills). Codex: new section listing
  `Data.ENEMIES + Data.BOSSES` by name / « ??? », traits from the same FR
  label table as 2.7 (share the function).

### 6.6 Biome ↔ act alignment
`Data.biome_for_floor` currently spans 12 floors; an act is 6 real floors.
Change the mapping to derive from acts: biome index =
`int(map_act / 2) % BIOMES.size()` — requires passing `map_act` (or
computing it from floor) — simplest: `biome_for_floor(floor)` with
`BIOME_SPAN := 12` already yields exactly 2 acts per biome **once 1.1 makes
floors start at 1** — verify the boundaries land after boss floors
(floors 1-12 = plaine = acts 1-2, boss floors 7 and 13… floor 13 is foret's
first floor and an act-1 boss — off by one act boundary). Fix by defining
strata explicitly: biome switches when `map_act` is even, applied in
`generate_floor` via a biome chosen from `map_act / 2` instead of
`floor_num`. Give each boss a home biome note in its Data entry (flavor
only for now).

### 6.7 Barks + the pre-existing roadmap
- `Barks.gd` (data): pools keyed by trigger — `biome_enter/<id>`,
  `low_hp`, `boss_intro/<sprite>/<times_faced 0|1|2+>`, `boss_kill`,
  `echo_seen`; `GameState.boss_faced: Dictionary` persists rematch counts.
- `Main.bark(speaker_pos, text, color)` → log line + MapView floater
  (reuse the damage-number pipeline, 2.5 s, italic prefix « Aria : »).
  Rate-limit: max 1 bark per 10 turns, never repeat the last line. **One
  line max, always.**
- Then: Forge du Hub, Boutique du Hub, dialogues, lore/endings — design on
  arrival, consistent with RESUME_SESSION's notes.

### 6.8 Optional signature — Echoes (VISION.md §2.B)
- On death, serialize into the save: `echo = {floor, level, loadout,
  equipment, powers, max_hp, atk}`. **Trap**: item dicts contain `Color`
  objects (`rarity_color`) — JSON round-trip destroys them. Write a
  `_color_to_save` / `_color_from_save` pair (store `.to_html()`) applied
  over equipment dicts, or store only what the echo needs (names, bonus,
  procs) and rebuild colors from `rarity`.
- Next run, entering floor `echo.floor`: spawn « l'Écho d'Aria » — sprite
  `aria`, `tint` arcane, boss-tier flag off, stats: `max_hp = echo.max_hp`,
  `atk = int(echo.atk * 0.9)`, behavior melee, `awake = true`, carries the
  echo's `frappe_double`-style proc if its weapon had one. On kill: a
  CHOICE overlay to claim ONE item of `echo.equipment`. Echo consumed on
  kill only; one stored (newest replaces). Clear on victory (when endings
  exist).

---

## PHASE 7 — Engineering hygiene (continuous; start right after Phase 1)

### 7.1 CI (do this first — it protects everything else)
`.github/workflows/smoke.yml`:
```yaml
name: smoke
on: [push, pull_request]
jobs:
  smoke:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/cache@v4
        with: { path: godot, key: godot-4.3-stable }
      - run: |
          if [ ! -x godot/Godot ]; then
            mkdir -p godot && curl -sSL -o g.zip https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip
            unzip -q g.zip -d godot && mv godot/Godot_v4.3* godot/Godot && chmod +x godot/Godot
          fi
      - run: godot/Godot --headless --editor --quit --path . || true   # import pass; may warn
      - run: test -d .godot                                            # import actually ran
      - run: godot/Godot --headless --path . res://_SmokeTest.tscn 2>&1 | tee out.log
      - run: grep -q "SMOKETEST PASSED" out.log
```
Also **seed the smoke test** (`seed(4242)` in `_smoketest.gd::_ready`) —
its random-walk section currently uses the unseeded global RNG (flaky by
design). Once Phase 8 lands, append the `_art_check.gd` validator as a step.

### 7.2 Save versioning + migration
- `save_game` writes `"version": 2`. `load_game`: read
  `int(parsed.get("version", 1))`; a `match` ladder migrates upward
  (v1→v2: fill `settings` defaults, `kill_counts = {}`, rename codex
  buckets when 6.4 lands — each schema change bumps the version and adds a
  branch). Unknown future version: log and load best-effort. **Never crash
  on any historical save**; assert in the smoke test by feeding a
  hand-written v1 JSON through `load_game`.

### 7.3 Split `Main.gd` (do when Phase 2 lands — it touches the AI anyway)
Four `RefCounted` modules, each `_init(game)` holding a back-reference;
Main keeps thin delegating methods so `Hud`'s `game.*` bindings never
change. **One extraction per commit, smoke test green after each.**
- `scripts/EnemyAI.gd`: `_enemy_act*`, `_enemy_step_toward/away`,
  `_enemy_atk`, `_enemy_cast/summon/sacrifice`, `_count_allies_near`,
  `enemy_intent`.
- `scripts/CombatSystem.gd`: `_player_attack`, `_enemy_attack_player`,
  `_enemy_hit_player`, `aoe/pierce/bounce/dash`, all `apply_*`,
  `_trigger_weapon_prefixes`, `_fire_prefix_damage`, `push_entity`,
  `_check_revive`.
- `scripts/LootSystem.gd`: `_spawn_loot`, `_pickup_loot_at`, `_bag_add`,
  equip/unequip/salvage/consumable, `_drop_skill/_drop_power`,
  `_acquire_*`, `_pick_*_def`.
- `scripts/RunProgression.gd`: `_roll_node_type`, `_advance`,
  `_node_cleared`, floor rewards, shop/event/rest/forge handlers.
Shared state (player, enemies, rng, floor_num…) stays on Main; modules
reach it via `game.`.

### 7.4 Freeze `gen.py`
Delete it (preferred — nothing imports it) or prepend a frozen-legacy
header naming `_assets_gen.gd` as sole source of truth. **Must precede any
Phase 8 work.**

### 7.5 Dead code & assets
Remove `knight/mage/ranger` from `MapView._load_textures` (MapView.gd:80),
their `_fig_*`/`_gen_creature` entries, and the PNGs (+ `.import`). Dedupe
ASCII fallback glyph collisions: Drake `"k"`→`"K"` vs Kobold; Ours `"B"`→
`"U"` vs bosses (Data.gd ENEMIES).

### 7.6 Explicit `wtype` on unique weapons
Add `"wtype"` to every arme entry in `Data.UNIQUE_BASES` (17 entries — from
their names: Arc du Vent = ranged; Bâton/Sceptre = magic; rest melee),
read it in `_make_unique_item`, then delete `infer_weapon_type`
(Data.gd:96) and its call site (Data.gd:603).

### 7.7 HUD rebuild churn
`Hud.refresh` rebuilds artifact/power/synergy/status boxes every action
(Hud.gd:1017-1074). Cache a fingerprint per box (e.g. joined ids/turns
string); rebuild only when it changes.

### 7.8 Housekeeping
LICENSE (ask the owner; default MIT), `export_presets.cfg`
(Linux/Windows/Web), README corrections beyond Phase 1's, and the branch
cleanup noted in RESUME_SESSION once the default branch changes.

---

## PHASE 8 — Art direction: generator upgrade & 64×64 migration

**Full detail lives in two places** — this section is deliberately short:
- `ART_GENERATOR_SPEC.md` — exact algorithms, color math, naming
  conventions, MapView integration, execution checkpoints **C1-C10** for
  the technique upgrades (8.A): per-sprite RNG reseeding, hue-shifted
  ramps, selective outlines, ground variants + seam removal, water/lava
  shoreline autotiling, road overlay blending, tall trees, animation
  frames, creature composition kit, contact sheets, readability validator,
  UI pixel icons + 9-patch panels. **Follow that file.**
- 8.B (the 64×64 migration) decision table and wave plan:

| Option | Viewport | Visible play area | Verdict |
|---|---|---|---|
| **B1 (recommended)** | **1920×1080**, CELL 64, sidebar 576, log 132 | ~21×15 tiles | Range-7 enemies fit with margin; UI gains room for the pixel font. Smaller screens scale via `canvas_items` stretch. |
| B2 | 1280×720, CELL 64 | ~14×9 tiles | Range-7 enemies can shoot from screen edge. Rejected. |
| B3 | stay 32×32, ship only 8.A | unchanged | Legitimate fallback — 8.A alone is ~70 % of the visual gain. |

Waves (each: regen → import → contact sheet → xvfb screenshot at 1080p AND
a scaled 1366×768 window → validator green → smoke green):
**W0** prerequisites (7.4 done, 8.A complete, viewport+anchor switch);
**W1** `TILE` 32→64 behind a redrawn-set registry (non-redrawn sprites
nearest-upscale 2× at save time — game stays coherent);
**W2** terrain (80 % of screen pixels — grounds/water sets/trees 64×96/
rocks/roads per biome); **W3** Aria (3 views × 2 frames) + bosses at 96×96
overflowing their tile (bottom-anchored oversize draw path in MapView);
**W4** the 25 common enemies via the composition kit; **W5** props, POI,
loot, buildings (128×176), node icons, UI icons at 24-32 px, and a real
generated 1920×1080 title illustration replacing `TitleBg.gd` via the
existing `assets/title_bg.png` hook (Hud.gd:435).

Touchpoints for the CELL/viewport switch: `_assets_gen.gd:12` (TILE),
`MapView.gd:5` (CELL), `TownView.gd:8-10` (CELL/BW/BH), `project.godot`
viewport, `Hud.gd:7-9` + font sizes, `EquipPanel.gd` coords,
`Hud._sprite_portrait` (72 px), `_draw_hp_pip` metrics, README. Camera math
and torch/vignette radii derive from CELL/view_size — verify only.

**Phase 8 done when**: 8.A checkpoints C1-C10 all pass; B1 shipped through
W5 (or B3 explicitly chosen and recorded here); no emoji in the UI; README
art section updated.

---

## What NOT to do (hard constraints)

- No new parallel systems: every addition must deepen an existing system or
  the Phase 4 hook.
- No additional playable heroes.
- No map size increases; don't raise `MAP_MAX_H` (lowering it to ~240 until
  density work exists is allowed — see AUDIT §3.4).
- No multiplayer/online features.
- No walls of lore text; barks are one line.
- Don't convert the game to English; don't mix English into player-facing
  text.
- Don't replace the code-generated art pipeline with external art without
  being asked (the Phase 3.1 font and its license file are the sole
  sanctioned exception).

## Definition of done (overall)

1. Smoke test green, extended with regression asserts for every Phase 1
   bug, the Phase 2 LoS/aggro/intents behaviors, the Phase 3 seed
   determinism, and every Phase 4 interaction.
2. CI runs it (plus the art validator) on every push.
3. A full keyboard-only run is playable: title → hub → run → pause →
   death recap → title, at 4:3 / 16:9 / 21:9.
4. `README.md` / `RESUME_SESSION.md` accurate; `AUDIT.md` items checked off
   in-file (✅ + commit hash).
5. Balance sim CSVs (before/after) committed under `docs/balance/` for
   Phase 5.
