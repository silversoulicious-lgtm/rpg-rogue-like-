# Implementation Guide — « Les Strates »

> **Purpose**: self-contained work order for an AI agent (or any developer)
> executing the findings of `AUDIT.md` (bugs & issues) and `VISION.md`
> (differentiation & polish). You should be able to work from this file alone;
> AUDIT.md and VISION.md contain the extended rationale if needed.
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
  commit messages, README). Keep it that way. Code identifiers are a
  French/English mix — match the local style of whatever file you touch.
- **All art is code-generated** pixel sprites (32×32) in `assets/*.png`,
  produced by `_assets_gen.gd`. There is a Python mirror `gen.py` (legacy).
- **No scenes to speak of**: `scenes/Main.tscn` is one node; the whole game is
  built in code.

### File map

| File | Role | Size |
|---|---|---|
| `scripts/Main.gd` | God object: state machine, floor generation, combat, enemy AI, skills, loot, shop/events/rest, turn loop | ~2 180 lines |
| `scripts/Hud.gd` | ALL UI: sidebar, log, title, loadout, meta screens, overlays | ~1 075 |
| `scripts/Data.gd` | Static data registry: heroine, 25 enemies, 10 bosses, skills, items, affixes, prefixes, uniques, talents, artifacts, powers, events, upgrades, knowledge tree, oaths | ~890 |
| `scripts/Entity.gd` | Pure-data grid entity + derived stats + statuses | ~290 |
| `scripts/Dungeon.gd` | Procedural open-world floor gen + fog of war | ~265 |
| `scripts/GameState.gd` | Autoload: persistent meta-progression, JSON save (`user://save.json`) | ~175 |
| `scripts/MapView.gd` | Tile/entity rendering, fog, camera, FX layer, atmosphere | ~430 |
| `scripts/Town.gd` / `TownView.gd` | Hub (fixed little town) model + renderer | ~155 |
| `scripts/Ui.gd` | Widget factory (labels/buttons/styles) | ~150 |
| `scripts/EquipPanel.gd`, `TitleBg.gd` | Sidebar equipment silhouette; procedural title backdrop | small |
| `_smoketest.gd` + `_SmokeTest.tscn` | Headless smoke test driving full runs | ~710 |
| `_assets_gen.gd` | Sprite generator (source of truth for art) | ~2 190 |
| `gen.py` | Python mirror of the generator (legacy, to be frozen) | ~1 990 |

### Tooling — how to build, test, verify (works in a sandbox)

```bash
# 1. Get Godot 4.3 headless (Linux):
curl -sSL -o godot.zip https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip
unzip -q godot.zip && chmod +x Godot_v4.3-stable_linux.x86_64

# 2. MANDATORY first run — populates class cache & imports assets.
#    Re-run after generating any new PNG, or on "Identifier not declared" errors:
./Godot_v4.3-stable_linux.x86_64 --headless --editor --quit --path .

# 3. Run the smoke test (must print "=== SMOKETEST PASSED ==="):
./Godot_v4.3-stable_linux.x86_64 --headless --path . res://_SmokeTest.tscn

# 4. Regenerate sprites after editing _assets_gen.gd:
./Godot_v4.3-stable_linux.x86_64 --headless --path . --script res://_assets_gen.gd

# 5. Real rendering / screenshots (headless uses a dummy driver — no pixels):
#    run under xvfb-run WITHOUT --headless, with --rendering-driver opengl3,
#    via an `extends SceneTree` script that instantiates the scene, waits a few
#    process_frame, then root.get_texture().get_image().save_png(...).
```

### Working rules

1. **Never break the smoke test.** Run it after every task. When you fix a bug
   listed below, ADD an assert to `_smoketest.gd` that would have caught it.
2. **One phase = one coherent commit series.** French commit messages,
   imperative mood, matching the existing history style
   (e.g. « Corrige le décalage d'étage et ajoute un assert de régression »).
3. **Update the docs you invalidate**: `README.md` and `RESUME_SESSION.md`
   must stay truthful after your changes.
4. Work through phases **in order**. Within a phase, tasks are ordered by
   dependency. Do not start a later phase while an earlier one is red.
5. When a balance number is not specified, choose something sane, mark it with
   a short comment, and keep it in `Data.gd` (data-driven, tunable).
6. Do not add new third-party dependencies. Do not rewrite systems that work.

---

## PHASE 1 — Bug fixes (confirmed defects; small, high value)

### 1.1 Floor off-by-one
- `Main.start_run()` sets `floor_num = 1` (Main.gd:222) then calls
  `_advance("combat")` which does `floor_num += 1` (Main.gd:354) → the first
  floor displays « Étage 2 ». Fix so the first playable floor is 1
  (simplest: initialize `floor_num = 0`).
- Ripple check: `best_floor` records, Knowledge gain
  (`floor_num - GameState.best_floor`, Main.gd:2107), `biome_for_floor`,
  enemy `min_floor` gating, item scaling all consume `floor_num`.
- **Accept**: smoke test asserts `floor_num == 1` right after `start_run()`;
  HUD shows « Étage 1 » on a new run.

### 1.2 Boss power drop is dead code
- `on_enemy_killed`: `if floor_num % 15 == 0: _drop_power(...)`
  (Main.gd:1305). Boss floors are ≡ 1 mod 6 → the condition is never true.
- Replace with an act-based rule: e.g. drop a power after every 2nd Guardian
  (`map_act % 2 == 0` at kill time) — pick and document the cadence.
- **Accept**: smoke test simulates 2+ boss kills and asserts a power drop
  occurred at the chosen cadence.

### 1.3 `weaken` has no effect on enemies (Représailles prefix is a no-op)
- Only `_player_def()` (Main.gd:1077) reads `weaken`. `_enemy_atk()`
  (Main.gd:1706) must subtract the enemy's own `weaken` status value
  (floor at some minimum, e.g. 1).
- **Accept**: smoke test applies weaken to an enemy and asserts its effective
  attack drops.

### 1.4 Boss shield-guardians spawn anywhere on the map
- `_boss_on_spawn` uses `dungeon.random_floor_tiles(...)` over the whole map
  (Main.gd:534). Spawn them within ~6 tiles of the boss instead (reuse
  `_free_adjacent` / a radius-limited sampler; fall back to global only if no
  local tile exists).
- Also **kill remaining guardians when their boss dies** (they currently
  linger as inert 0-ATK husks — check `guard_for` in `on_enemy_killed`).
- **Accept**: smoke test spawns a guardian boss and asserts all its guardians
  are within radius; killing the boss removes them.

### 1.5 Uncapped dodge / crit / lifesteal
- `Entity.recompute_stats` (Entity.gd:240-255) never clamps. Caps:
  `dodge_chance ≤ 0.60`, `crit_chance ≤ 0.75`, `lifesteal_pct ≤ 0.50`
  (constants in `Data.gd`).
- **Accept**: smoke test stacks dodge sources past the cap and asserts the
  clamp.

### 1.6 Forge amplifies maluses
- `forge_choice` (Main.gd:2068-2089) scales bonuses by sign
  (`signi(int(v))`) → negative stats get MORE negative. Skip non-positive
  values (leave maluses untouched).
- **Accept**: forging an item with `speed: -5` leaves it at -5.

### 1.7 AZERTY-hostile input
- `_unhandled_input` compares `event.keycode` (Main.gd:731). Switch to
  `event.physical_keycode` (minimum), or better: define actions in the
  InputMap (project.godot) — `move_up/down/left/right`, `wait`, `ability`,
  `inventory`, `cancel` — and use `Input.is_action_*` / `event.is_action_*`.
  Keep arrows + HJKL working.
- **Accept**: movement works from physical WASD positions regardless of layout.

### 1.8 No pause / no way to quit a run
- In `State.PLAYING`, Escape opens a pause overlay: **Reprendre / Options /
  Abandonner l'ascension**. Abandon banks the run's Shards like death does
  (reuse the `game_over` banking path; a small penalty like ×0.75 is
  acceptable — document the choice) and returns to title.
- **Accept**: Escape in-run pauses; abandoning banks shards (smoke-testable
  via direct method call).

### 1.9 UI breaks off 16:9
- HUD is absolutely positioned against `VIEW = 1280×720` (Hud.gd:7,79,191,304;
  TownView.gd:11) while `project.godot` uses `stretch/aspect="expand"`.
  Either (a) anchor sidebar/log/buttons to viewport edges with `PRESET_*`
  anchors and derive `play_area()` from the real viewport size, or
  (b) switch to `aspect="keep"` (letterboxing) and document it. Option (a)
  preferred.
- **Accept**: resize the window to 4:3 and 21:9 → sidebar hugs the right edge,
  log hugs the bottom, no floating panels (verify via xvfb screenshot).

### 1.10 Oath of Poverty leaks a starting bonus
- « Aucun bonus de départ » but `Pacte de Pouvoir` still grants a starting
  power (Main.gd:256). Gate it behind `not has_oath("pauvrete")` and update
  the oath description if needed.
- **Accept**: smoke test with the oath active starts with zero powers.

**Phase 1 done when**: all 10 fixed, smoke test green with ≥6 new asserts,
README updated where it lied (sprites are 32×32 not 24×24, README.md:142;
Guardian cadence is every 6 real floors, README.md:12 — either fix the text
or change `ACT_LENGTH` behavior to match the text, your call, but be
consistent).

---

## PHASE 2 — Combat fairness (the felt-quality core)

### 2.1 Shared line-of-sight for ranged combat
- Implement a Bresenham LoS check in `Dungeon` (blocked by WALL/TREE/ROCK;
  WATER does not block sight).
- Enemy ranged/caster attacks (`_enemy_act_ranged`, `_enemy_cast`,
  Main.gd:1766-1814) require: target within the ATTACKER's range AND clear
  LoS AND the enemy is inside the player's *current vision* (no shots from
  the void).
- Player auto-targeting (`_nearest_enemy_in_range`, Main.gd:959) only
  considers **visible** enemies with clear LoS. `dash_strike`'s range-99
  scan obeys the same rule. AoE (`aoe_attack`) only hits targets with LoS
  from the blast center. The Drone/Turret powers target visible enemies only.
- **Accept**: smoke test placing a wall between player and archer asserts no
  hit in either direction.

### 2.2 Vision vs enemy range
- `BASE_VISION = 4` (Data.gd:106) vs enemy ranges up to 7. Raise base vision
  to 6 **or** clamp effective enemy attack range to the player's current
  vision. Choose one; document it.

### 2.3 Aggro radius (kill the omniscient AI)
- Enemies start **dormant**. Wake when: player enters `aggro_radius`
  (default ~8, overridable per enemy in `ai`), they take damage, or a woken
  ally within ~4 tiles shouts. Dormant enemies skip their act (but still
  regen). Bosses always awake.
- **Accept**: on a large map, distant enemies don't converge from turn 1.

### 2.4 Minimal obstacle avoidance
- `_enemy_step_toward` is a 2-direction greedy (Main.gd:1668) — enemies stall
  behind lakes forever. For bosses and elites, add a bounded A* (≤ ~24 steps,
  cached a few turns); for common enemies, add a third fallback: try the
  diagonal, then a random perpendicular sidestep.
- **Accept**: a boss separated from the player by a small lake reaches the
  player within a reasonable number of turns in a scripted smoke scenario.

### 2.5 Telegraphed enemy intents
- Each awake enemy exposes its next action (`attack`, `shoot`, `cast`,
  `charge`, `flee`, `sleep`) — derive from its behavior + cooldown state
  BEFORE it acts. `MapView` draws a small intent glyph above visible
  enemies (⚔ / ➶ / ✦ / ⚡ / 💤). Keep it readable at 32 px.
- **Accept**: visible in a screenshot; the mapping is data-driven, not a
  second copy of the AI logic (compute intent in one function reused for
  display).

### 2.6 Turn-order strip
- The energy/speed system is invisible. Add a small horizontal strip (sidebar
  or top of play area) previewing the next ~8 actors (mini sprite + name on
  hover), computed by simulating energy accrual without side effects.
- **Accept**: strip updates every player action; slowed enemies visibly drop
  back.

### 2.7 Enemy inspection
- Hovering (or a `x`-key examine cursor) over a visible enemy shows a tooltip:
  name, HP, ATK, speed, behavior label, on-hit status, resists/weaknesses —
  all straight from the entity/`ai` dict. Mimic shows chest info until
  revealed (don't leak it — also stop drawing the HP pip for unrevealed
  mimics, MapView.gd:417).
- **Accept**: tooltip shows correct data for 3 different enemy archetypes.

**Phase 2 done when**: all six in, smoke test green, and a manual xvfb
screenshot shows intents + turn strip rendering correctly.

---

## PHASE 3 — Feel & polish pass (the “real game” signals)

Do these in order; they are cheap and transform perception.

### 3.1 Pixel font
- The whole UI uses `ThemeDB.fallback_font`. Add a bitmap pixel font
  (generate one via `_assets_gen.gd` as a texture font, or add a public-domain
  .ttf like m5x7 — CC0 assets are acceptable) and route ALL text through it:
  set a default theme in `Main._ready`/`Ui.gd` rather than touching every
  label. Check French diacritics (é è à ç œ) render.
- **Accept**: screenshot shows the new font on title, HUD, overlays; no
  missing-glyph boxes on accented text.

### 3.2 Sound
- Add a tiny SFX layer (`Sfx.gd` autoload, `AudioStreamPlayer` pool).
  Generate the 10 core sounds procedurally as WAV at build time (a
  `_sfx_gen.gd` sibling of `_assets_gen.gd` — square/noise blips are fine and
  fit the aesthetic) or add CC0 files: hit, crit, kill, pickup, level-up,
  stairs, purchase, heal, UI click, danger/boss.
- Hook them: `_player_attack`, `on_enemy_killed`, `_pickup_loot_at`,
  `_check_level_up`, `_node_cleared`, shop buy, `use_consumable`, UI buttons
  (via `Ui.button`), boss spawn.
- Volume sliders (master/SFX) in Options, persisted in `save.json`.
- **Accept**: headless-safe (no crash without audio device); options persist.

### 3.3 Movement & combat juice
- Tween entity movement between tiles (~0.08 s, `MapView` visual offset only —
  logic stays instant), attack lunge already exists (`fx_attack`).
- Floating damage numbers (crit = bigger/gold, heal = green) as a `MapView`
  FX; hook where `take_damage`/`heal` results are known in Main.
- 2-frame hit-stop on player crits; 3-4 px screenshake on crit/boss rage
  (offset `MapView.position`, respect an Options toggle).
- **Accept**: screenshot mid-combat shows damage numbers; shake toggle works.

### 3.4 Input responsiveness
- Hold-to-repeat movement (initial delay ~0.25 s, repeat ~0.09 s) via
  `_process` polling of the InputMap actions from 1.7 — but only in
  `State.PLAYING`, and never faster than the game can resolve turns.
- Keyboard navigation of overlays: reward/event/rest/levelup buttons
  selectable with arrows + Enter (grab focus on first button when shown).
- **Accept**: holding a direction walks smoothly; a full run is playable
  without the mouse.

### 3.5 Ambient particles per biome
- `MapView`: lightweight `CPUParticles2D` (or hand-drawn in `_draw`) per
  biome — leaves (forêt), snow (toundra), ash (volcan), fireflies (marais),
  dust (désert), pollen (plaine) + torch embers near Aria. Data-driven from
  a new `ambient` key in `Data.BIOMES`.
- **Accept**: screenshots of 2 biomes show distinct ambience; no perf hit.

### 3.6 Death recap that sells the next run
- Track cause of death (last damage source name) in Main; show on game over:
  « Tuée par X à l'Étage N ». Add a compact run timeline (per act: floors
  cleared, boss beaten, best item) and « à N étages de ton record » when
  close.
- **Accept**: dying to a specific enemy names it on the death screen.

### 3.7 Log & seeds
- Scrollable message log (keep last ~200 messages; RichTextLabel with
  scroll, autoscroll on new).
- Seed the run: display seed on HUD/death screen; `start_run` accepts an
  optional seed; route ALL gameplay randomness through `Main.rng` (replace
  `pool.shuffle()` in Hud.show_levelup, Hud.gd:830, and any global-RNG use).
- **Accept**: two runs with the same seed and same inputs produce identical
  first floors (smoke-testable).

**Phase 3 done when**: all seven in, smoke test green, README « Interface »
section updated.

---

## PHASE 4 — The hook: elemental terrain (vertical slice first)

Full rationale in VISION.md §2.A. **Build ONE biome's interaction first,
validate, then extend.**

### 4.1 Vertical slice — fire spreads in the Forêt biome
- New terrain state layer in `Dungeon` (e.g. `effects[y][x]`: none/burning/
  burnt/frozen…, with per-cell timers), ticked once per player turn from
  `advance_world`.
- Rules for the slice:
  - Any `burn` application on/adjacent to a TREE tile ignites it (sources:
    the `ardent` prefix, `ember`/`fireball` skills, Élémentaire de feu,
    explosions).
  - A burning tree: emits fire FX, each tick deals burn to entities in the
    8 neighbors, then has a chance (~35 %/tick) to spread to adjacent TREEs;
    after 3-4 ticks it becomes `burnt` ground (**walkable** — obstacle gone).
  - Entities standing in flames get the existing `burn` status (respect
    `immune_fire` / `weak_fire`).
  - Fog rules apply: you only see fire you can see.
- `MapView`: burning overlay (animated 2-frame flame from `_assets_gen.gd`)
  + `burnt` ground variant sprite.
- **Accept**: smoke test scenario — place trees, ignite one, tick N turns,
  assert propagation, damage to an adjacent entity, and tile → walkable burnt
  ground. Manual screenshot of a burning forest.

### 4.2 Evaluate, then extend (only if 4.1 plays well)
- **Eau + foudre**: lightning damage on a target standing in/adjacent to
  WATER chains (reuse `bounce_attack`) to all enemies in the same connected
  water body (flood-fill, cached).
- **Givre + eau**: slow/frost effects on WATER freeze it into walkable ice
  for ~10 turns (new tile state; melts back; fire melts it instantly).
- **Marais**: poison clouds (cell effect) left by some enemies/deaths.
- **Volcan**: 1-2 slow lava fronts advancing along a precomputed path.
- Each interaction: same acceptance pattern — a scripted smoke scenario +
  a screenshot.
- Update weapon prefixes/skills descriptions to mention terrain synergies.

### 4.3 Knockback (multiplies the hook)
- Add a push primitive (`push(entity, dir, tiles)`): moving into water =
  brief `slow` + repositioning; into fire = burn; into a trap = trigger it.
  Give it to: a new melee skill, 1-2 enemies (Bélier-type), and the charger
  behavior (small knock on charge hit).
- **Accept**: smoke scenario pushes an enemy into water and asserts the
  status.

**Phase 4 done when**: Forêt slice + at least two more biome interactions
shipped, each with tests; VISION.md updated with what was validated/cut.

---

## PHASE 5 — Balance instrumentation & tuning

### 5.1 Autoplay harness
- `_balance_sim.gd` (SceneTree script, headless): plays N runs (e.g. 200)
  with a simple policy (move toward nearest visible enemy, use ability when
  ready, drink potion < 35 % HP, equip strict upgrades). Outputs CSV:
  seed, death floor, death cause, level, kills, shards, best item rarity,
  turns played.
- **Accept**: one command produces the CSV; document it in README.

### 5.2 Tune with data (targets, adjust in `Data.gd`/`Main.gd`)
- Median death floor for a no-meta run: ~10-14. If the sim says otherwise,
  adjust: enemy scale slope (Main.gd:593, currently ×1+0.12/floor on HP&ATK),
  scale enemy defense too (currently unscaled, Main.gd:603), item scale slope
  (Data.gd:628).
- **Decouple XP from shard value** (Main.gd:1268): add an `xp` field per
  enemy def; soften the level flood (curve like `10 + level² × 3`).
- Economy pass: shop prices vs income, salvage, Moisson values, Knowledge
  node costs, oath rewards. Make the gamble event an actual gamble
  (negative-EV-tinged risk, Main.gd:1992).
- Enemy pool weighting: add optional `max_floor`/weights so floor 30 isn't
  the same 25 monsters with bigger numbers (Data.gd ENEMIES + Main.gd:581).
- **Accept**: before/after sim CSVs committed (in `docs/` or the PR
  description), showing movement toward targets.

---

## PHASE 6 — Content depth (only after Phase 5 exists)

1. **Talents**: replace at least half of the flat `+stat` talents
   (Data.gd:703-720) with mechanical ones (DoTs tick twice; +1 projectile
   bounce; traps become allies; killing a burning enemy spreads fire; etc.).
   Keep the data-driven `mods` shape where possible; add a `hook` field
   interpreted by Main for the mechanical ones.
2. **Elite affixes**: elites get 1 random affix (rapide / explosif /
   régénérant / voleur / chef de meute…) + a visible tint (modulate) and the
   affix in their display name — replaces the flat ×1.25 stat sponge
   (Main.gd:472-476).
3. **Pool expansion**: artifacts 5 → ~15, powers 5 → ~12, events 7 → ~20
   (some biome-specific), consumables 4 → ~10 (bombe, antidote, parchemin de
   téléport, huiles d'arme élémentaires — synergy with Phase 4).
4. **Merge artifacts + powers into one « Reliques » system** (VISION.md §6):
   one list, one UI section, rarity tiers; migrate `ARTIFACT_MODS`/`POWER_MODS`
   into one registry. Update Codex categories and `GameState.discovered`
   (bump save version, see 7.2).
5. **Bestiary in the Codex**: monsters + bosses as a category; entries fill
   in as you fight them (name at first sight, traits after N kills).
6. **Align biome ↔ act**: make each act happen inside one biome
   (`BIOME_SPAN` derived from act length) and give each boss a home biome.
7. Then the pre-existing roadmap: Forge du Hub, Boutique du Hub, dialogues
   (with the barks system below), lore/endings.

### Narrative barks (cheap, do alongside 6.7)
- A `Barks.gd` data file: one-liners for Aria (biome entry, low HP, boss
  rematch, echo encounter), boss intros (2-3 variants keyed on times faced —
  persist a counter in `GameState`), hub NPC lines reacting to `last_run`
  (death cause, boss killed). Display: log + a small speech bubble above the
  speaker in MapView. **One line max, always.**

### Optional signature feature — Echoes (VISION.md §2.B)
- On death, serialize the build (equipment, talents, skills, powers, level,
  floor) into `save.json`. Next run, on that floor, spawn « l'Écho d'Aria »:
  a boss-tier enemy using `copy_player`-style logic but driven by the DEAD
  build's stats/procs. On kill: pick ONE item from the echo's gear.
  Cap: one echo stored (newest replaces).
- **Accept**: die with a distinctive item → next run's echo drops offer
  contains it.

---

## PHASE 7 — Engineering hygiene (continuous, start anytime after Phase 1)

1. **CI**: GitHub Actions workflow — cache the Godot 4.3 binary, run the
   editor import step, run `_SmokeTest.tscn`, fail on non-zero / missing
   « SMOKETEST PASSED ». Seed the smoke test RNG for determinism.
2. **Save versioning**: add `"version": 2` to `save.json`; on load, migrate
   older shapes (missing keys → defaults). Never crash on an old save.
   Required before the Reliques merge (6.4).
3. **Split `Main.gd`** (do this when Phase 2 lands, it touches AI anyway):
   extract `EnemyAI.gd` (behaviors), `CombatSystem.gd` (attacks/procs/statuses
   application), `LootSystem.gd` (drops/inventory ops), `RunProgression.gd`
   (node rolling/acts/rewards). `Main` keeps state + input + orchestration.
   Pure refactor: smoke test must pass unchanged at each extraction step.
4. **Freeze `gen.py`**: add a header comment marking `_assets_gen.gd` as the
   only source of truth, or delete `gen.py` (preferred if nothing imports it).
5. **Dead code/assets**: remove `knight/mage/ranger` from MapView texture
   list (MapView.gd:80) and delete unused PNGs; dedupe ASCII glyph collisions
   (Drake vs Kobold « k », Ours vs boss « B »).
6. **Explicit `wtype` on unique weapons** (Data.gd UNIQUE_BASES) — delete the
   name-sniffing `infer_weapon_type` (Data.gd:96).
7. **HUD rebuild churn**: only rebuild artifact/power/synergy/status boxes on
   change (dirty flag), not every action (Hud.gd:1017-1074).
8. **Housekeeping**: LICENSE file (ask the owner which; default MIT for code,
   note assets are generated), `export_presets.cfg` for Linux/Windows/Web,
   README corrections (32×32, real Guardian cadence, controls incl. new
   pause/examine keys).

---

## PHASE 8 — Art direction: generator upgrade & 64×64 migration

> **Where it slots**: 8.A (technique upgrades) right after Phase 3 — they
> multiply the value of every screenshot taken later. 8.B (the 64×64
> migration) is independent of Phases 4-6 and can interleave with them,
> wave by wave. Do **not** start 8.B before 8.A is done: redrawing 80+
> sprites with the old techniques would be wasted work.

### Current state of the generator (read this before touching it)

`_assets_gen.gd` (~2 190 lines) draws every sprite from scratch with pixel
primitives (`_px/_rect/_ellipse/_trapezoid/_line/_tri_up/_diamond`), plus
`_glow` (neon halo), `_ground_shadow`, 3-band shading (`_disc_band`/
`_tri_band`), Bayer 4×4 dithering on grounds, a named identity palette
(~20 constants: INK/STONE/STEEL/GOLD/ARCANE/CYAN/EMBER…), `TILE := 32`,
seeded RNG (1337). Each of the ~45 creatures is a bespoke `_fig_*` function
of 20-40 hardcoded coordinate calls. Buildings use `_new_sized` (64×88).
The instincts are good (top-left light, outlines, contact shadows, glow
accents). The ceiling comes from five specific limitations:

1. **Value-only shading**: all ramps are `darkened()/lightened()` — same hue,
   less/more value. Good pixel art hue-shifts: shadows slide toward
   indigo/violet, highlights toward warm; saturation drops in light. This is
   the single biggest "programmer art vs artist" tell.
2. **One tile per terrain type**: each biome has exactly one ground, one
   water, one tree, one rock texture, tiled infinitely → visible grid
   repetition, the #1 thing that screams "generated".
3. **No edge transitions**: water meets grass as a hard square seam; roads
   have no borders. No autotiling anywhere.
4. **No animation frames**: water is frozen, fires don't flicker (the idle
   "bob" in MapView is a position offset, not animation).
5. **Bespoke-code creatures**: 45 hand-coded figures means inconsistent
   proportions/quality across the bestiary and a high cost per new enemy.

Also note two coherence leaks outside the generator: the HUD uses **emoji
glyphs** (⚔ ✦ 🏪 ⚒ 📖…) rendered by the OS fallback font — they don't match
the pixel art at all and render differently per platform; and `Ui.gd`
styleboxes use rounded corners + soft shadows (vector look) against pixel
sprites. Both are fixed in this phase.

### 8.A — Generator technique upgrades (resolution-independent, do first)

> **Detailed spec**: `ART_GENERATOR_SPEC.md` gives the exact algorithms,
> color math, naming conventions, MapView integration points, execution
> order (checkpoints C1-C10) and known traps for everything in 8.A. Follow
> that file when implementing; the subsections below are the summary.

#### 8.A.1 Hue-shifted color ramps
- Add a `_ramp(base: Color, n: int)` helper producing n-step ramps that
  hue-shift toward the palette's indigo (`INK`) in shadow and toward warm
  white in highlight, with saturation peaking in the mid-dark steps.
- Define a central `RAMPS` table (material name → 5-color ramp: skin, steel,
  bone, rose, arcane, foliage-per-biome, stone-per-biome…). Replace direct
  `darkened/lightened` calls in figures/tiles with ramp lookups as they get
  touched (full sweep happens naturally during 8.B redraws).
- Emit a machine-checkable **palette report**: after generation, scan all
  PNGs, count distinct colors; warn above a budget (~64 total). Restraint is
  the style.
- **Accept**: a regenerated tree/rock/Aria visibly hue-shifts (screenshot
  comparison); palette report runs and passes.

#### 8.A.2 Consistent selective outlines (“selout”)
- Add a post-process `_auto_outline(img)` : from the silhouette (alpha mask),
  draw the outline INK only on bottom/right (shadow side) and a hue-shifted
  darker-fill color on top/left (lit side). Apply to every creature/prop
  after its figure function — removes the current per-figure inconsistency
  where some shapes carry `_o` outlined variants and some don't.
- **Accept**: contact sheet (8.A.6) shows uniform outline treatment.

#### 8.A.3 Tile variants + autotiling (biggest visual win, do not skip)
- **Ground variants**: generate 4 variants per biome ground
  (`plaine_ground_0..3` — same recipe, different seeds/detail placement).
  `MapView._draw_ground` picks per-cell via a stable position hash
  (`(x*7+y*13) % 4`). Kills the grid-repetition look for one afternoon of
  work.
- **Water shoreline autotiling**: generate a 4-bit edge set for water
  (16 tiles, or the 8-tile blob subset: straight edges N/E/S/W + inner
  corners), with a lighter bank line + 1px foam crest where water touches
  land. `MapView._draw_terrain` selects by neighbor bitmask (water/not-water
  in 4 directions). Same mechanism reused later for lava (Phase 4) and
  roads (road gets soft dirt edges).
- **Tall trees**: draw trees on a 32×48 (later 64×96) canvas anchored to the
  tile bottom so canopies overlap the tile above; MapView draws TREE cells
  in a second pass (after ground row y+1) so overlaps layer correctly.
  Instant depth.
- **Accept**: xvfb screenshot of a marais floor shows shorelines and
  non-repeating ground; smoke test green (pure rendering change).

#### 8.A.4 Animation frames (data convention: `name_f0.png`, `name_f1.png`…)
- Generator gains a frame parameter for: water (2 frames, crest offset),
  campfire (3-4 frames), glow decors (2 frames, pulse), torch/lantern.
  `MapView` cycles frames from `_anim_t` (~0.4 s step) when `name_f0`
  exists; falls back to the static name otherwise (zero-risk rollout).
- Creatures: keep the position bob, but add a real 2-frame idle for **Aria
  and the 10 bosses only** (breathing: 1px chest/head shift, glow pulse).
  Common enemies stay single-frame until 8.B wave 4.
- **Accept**: water shimmer + campfire flicker visible across two timed
  screenshots.

#### 8.A.5 Creature composition kit (pays for itself at 64×64)
- Extract reusable parameterized stamps from the existing figures:
  `_body_biped(ramp, w, h)`, `_body_quadruped(...)`, `_body_robed(...)`,
  `_head(style, ramp)`, `_weapon_stamp(kind)`, `_glow_eyes` (exists).
  A new creature becomes ~8 lines of composition + a ramp, instead of 40
  bespoke lines. Keep bespoke overrides for hero/bosses (they deserve it).
- This is also what makes **elite tints** (Phase 6.2) and legendary variants
  nearly free: same composition, shifted ramp + accent glow.
- **Accept**: at least 5 existing common enemies rebuilt on the kit with no
  visible regression on the contact sheet.

#### 8.A.6 Iteration & QA tooling (small, do before everything above)
- **Contact sheet**: `_assets_gen.gd` ends by composing
  `assets_preview.png` — every sprite on a grid, each rendered over two
  backgrounds (dark + its typical biome ground). This is how you review art
  in a headless sandbox; regenerate + view after every change.
- **Readability validator**: automated check rendering each creature over
  each biome ground and computing silhouette-edge luma contrast; fail under
  threshold. (Contrast bugs already happened once — commit 18514a5 — make
  the regression impossible.)
- **Icon set to replace emoji**: generate 16×16 (later 24×24) pixel icons
  for the sidebar stats, buildings, statuses, node types; swap Hud's emoji
  strings for TextureRects. Pixel-consistent UI across all platforms.
- **Pixel 9-patch panels**: generate a panel/button border texture and swap
  `Ui.gd`'s rounded StyleBoxFlat for StyleBoxTexture (crisp pixel corners).
  Pairs with the Phase 3.1 pixel font.
- **Accept**: contact sheet committed as a build artifact (or regenerated in
  CI); validator wired into the smoke test; no emoji left in the HUD.

### 8.B — The 64×64 migration

#### The decision, stated honestly
Sprites are drawn stretched into `MapView.CELL` rects. Feeding 64×64 art
into 32px cells would *downscale* it (half the pixels lost) — pointless. So
64×64 art requires `CELL = 64`, which forces a viewport decision:

| Option | Viewport | Visible play area | Verdict |
|---|---|---|---|
| **B1 (recommended)** | **1920×1080**, CELL 64, sidebar 576, log 132 | ~21×15 tiles | Max enemy range (7) fits with margin; matches modern displays; UI gets room for the pixel font. On smaller screens `canvas_items` stretch scales down — acceptable, add an integer-zoom option later if shimmer bothers. |
| B2 | keep 1280×720, CELL 64 | ~14×9 tiles | Too tight: range-7 enemies can shoot from off-screen edges. Rejected. |
| B3 | stay at 32×32, only do 8.A | unchanged | Legitimate fallback if effort is constrained — 8.A alone is ~70 % of the visual gain. |

Choose B1 unless told otherwise. Note: the 24→32 migration was already done
once (commit b33993e), so the codebase has survived this kind of change.

#### Why this is redraw work, not a constant change
Every `_fig_*` function hardcodes 32-space coordinates (center 16, feet
28-30). Doubling coordinates mechanically = chunky 2× upscale, zero new
detail. The gain of 64×64 (real facial features on Aria, readable weapon
shapes, textured fur/scales, 4-5 step ramps instead of 3) only exists if
sprites are **redrawn**. Hence waves, with an upscale fallback so the game
is shippable at every commit:

- **Wave 0 — prerequisites**: freeze/delete `gen.py` first (Phase 7.4 —
  never do this migration twice); 8.A complete; viewport/UI switch to
  1920×1080 (requires the anchor work from 1.9 and the pixel font from 3.1
  at the new scale).
- **Wave 1 — plumbing**: `TILE 32→64` behind a redrawn-set registry: any
  sprite not yet redrawn is generated at 32 and nearest-neighbor-upscaled
  2× at save time (visually identical to today). The game runs 100 %
  coherent from day one of the migration.
- **Wave 2 — terrain** (80 % of screen pixels): 6 biomes × (ground variants,
  water + shoreline set, tree at 64×96 tall-canvas, rock) + road with
  edges. Grounds gain a 3rd detail octave (pebbles, grass blades, cracks)
  — 64px is where Bayer dithering starts looking great.
- **Wave 3 — Aria + bosses**: Aria's 3 views ×2 idle frames at true 64
  (visible face, hair shapes, weapon silhouette per loadout would be a
  bonus). Bosses at **96×96 drawn overflowing their tile** (anchor-bottom,
  like Hub buildings) for presence — MapView needs an oversize-sprite draw
  path (bottom-anchored rect, drawn in the entity pass).
- **Wave 4 — the 25 common enemies** via the 8.A.5 composition kit, ~5 per
  session, contact-sheet-reviewed.
- **Wave 5 — props, POI structures, loot, node icons, buildings (128×176),
  UI icons at 24-32px, title illustration**: with the upgraded pipeline,
  generate a real layered 1920×1080 title backdrop (tower silhouette,
  starfield, fog bands, glow) to finally replace `TitleBg.gd`'s runtime
  placeholder via the existing `assets/title_bg.png` hook (Hud.gd:435).

#### Touchpoint checklist for the CELL/viewport switch (audit before, verify after)
- `_assets_gen.gd:12` (`TILE`), `MapView.gd:5` (`CELL`),
  `TownView.gd:8-10` (`CELL`, `BW`, `BH`), `project.godot` viewport size,
  `Hud.gd:7-9` (`VIEW`, `SIDEBAR_W`, `LOG_H`) + every font size,
  `EquipPanel.gd` hardcoded silhouette coords, `Hud._sprite_portrait`
  (72px), `MapView._draw_hp_pip` metrics, `Data.gd` comments, README.
- Auto-scaling already (verify only): camera math, torch pool/glow radii,
  vignette (all derive from `CELL`/`view_size`).
- **Accept per wave**: regenerate → editor import pass → contact sheet →
  in-game xvfb screenshot at 1080p AND a scaled 1366×768 window → readability
  validator green → smoke test green.

**Phase 8 done when**: 8.A all in; B1 shipped through wave 5 (or B3
explicitly chosen and documented in this file); `assets_preview.png`
regenerable; no emoji glyphs in UI; README's art section updated (64×64,
frame convention, how to review the contact sheet).

---

## What NOT to do (hard constraints)

- No new parallel systems: every addition must deepen an existing system or
  the Phase 4 hook.
- No additional playable heroes.
- No map size increases; don't touch `MAP_MAX_H` upward (lowering it to ~240
  until density work exists is allowed and encouraged — see AUDIT §3.4).
- No multiplayer/online features.
- No walls of lore text; barks are one line.
- Don't convert the game to English; don't mix English into player-facing text.
- Don't replace the code-generated art pipeline with external art without
  being asked.

## Definition of done (overall)

1. Smoke test green, extended with regression asserts for every Phase 1 bug
   and every Phase 4 interaction.
2. CI runs it on every push.
3. A full keyboard-only run is playable: title → hub → run → pause → death
   recap → title, at 4:3 / 16:9 / 21:9.
4. `README.md` / `RESUME_SESSION.md` accurate; `AUDIT.md` items checked off
   (edit the file: mark fixed items with ✅ and the commit hash).
5. Balance sim CSV before/after committed for Phase 5.
