## Contrôleur principal : flux d'écrans, tour-par-tour à énergie, combat, IA,
## capacités, équipement et artefacts.
## "Les Strates" — grimpe une tour façon Aincrad ; la mort améliore tes capacités.
extends Node2D

enum State { HUB, PLAYING, DEAD }

const MAP_W := 32
const MAP_H := 19
const BOSS_EVERY := 5          # un Gardien tous les 5 étages
const MAX_LOG := 8

var state: int = State.HUB
var rng := RandomNumberGenerator.new()

# Run en cours
var player: Entity = null
var enemies: Array = []         # Array[Entity]
var loot: Array = []            # Array[dict] : { pos, kind, glyph, color, data }
var dungeon: Dungeon = null
var floor_num: int = 1
var run_shards: int = 0
var meta_ability_power: int = 0
var messages: Array = []

# Noeuds
var map_view: Node2D
var hud_layer: CanvasLayer
var log_label: RichTextLabel
var menu_layer: CanvasLayer
var menu_content: VBoxContainer

# Sidebar (HUD permanent)
var sb_floor: Label
var sb_hero: Label
var hp_bar: ProgressBar
var hp_text: Label
var sb_ability: Label
var stat_labels: Dictionary = {}
var equip_box: VBoxContainer
var artifact_box: VBoxContainer

const VIEW := Vector2(1280, 720)
const SIDEBAR_W := 384
const LOG_H := 150

func _ready() -> void:
	rng.randomize()
	_build_nodes()
	show_hub("")

# --- Construction de l'interface ---------------------------------------------
func _build_nodes() -> void:
	var mv_script: Script = load("res://scripts/MapView.gd")
	map_view = Node2D.new()
	map_view.set_script(mv_script)
	add_child(map_view)

	hud_layer = CanvasLayer.new()
	add_child(hud_layer)
	_build_sidebar()
	_build_log()

	menu_layer = CanvasLayer.new()
	menu_layer.layer = 2
	add_child(menu_layer)

	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.04, 0.08, 0.96)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(center)

	menu_content = VBoxContainer.new()
	menu_content.add_theme_constant_override("separation", 9)
	menu_content.custom_minimum_size = Vector2(760, 0)
	center.add_child(menu_content)

# --- Sidebar (HUD permanent : stats + équipement + artefacts) -----------------
func _panel_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(8)
	s.set_content_margin_all(14)
	return s

func _build_sidebar() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(VIEW.x - SIDEBAR_W, 0)
	panel.size = Vector2(SIDEBAR_W, VIEW.y)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.09, 0.08, 0.13)))
	hud_layer.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.custom_minimum_size = Vector2(SIDEBAR_W - 56, 0)
	scroll.add_child(v)

	var title := Label.new()
	title.text = "⛫ LES STRATES"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.72, 0.62, 1.0))
	v.add_child(title)

	sb_floor = Label.new()
	sb_floor.add_theme_font_size_override("font_size", 16)
	sb_floor.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	v.add_child(sb_floor)

	sb_hero = Label.new()
	sb_hero.add_theme_font_size_override("font_size", 18)
	v.add_child(sb_hero)

	hp_text = Label.new()
	hp_text.add_theme_font_size_override("font_size", 14)
	v.add_child(hp_text)

	hp_bar = ProgressBar.new()
	hp_bar.show_percentage = false
	hp_bar.custom_minimum_size = Vector2(0, 18)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.3, 0.8, 0.35)
	fill.set_corner_radius_all(4)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.25, 0.07, 0.07)
	bg.set_corner_radius_all(4)
	hp_bar.add_theme_stylebox_override("fill", fill)
	hp_bar.add_theme_stylebox_override("background", bg)
	v.add_child(hp_bar)

	v.add_child(_section_header("STATISTIQUES"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	for pair in [["atk", "Attaque"], ["magic", "Magie"], ["defense", "Défense"],
			["speed", "Vitesse"], ["hp_regen", "Régén PV/tour"],
			["run_shards", "Éclats (run)"], ["bank", "Banque"]]:
		_make_stat_row(grid, pair[0], pair[1])

	v.add_child(_section_header("CAPACITÉ"))
	sb_ability = Label.new()
	sb_ability.add_theme_font_size_override("font_size", 14)
	sb_ability.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sb_ability.custom_minimum_size = Vector2(SIDEBAR_W - 56, 0)
	v.add_child(sb_ability)

	v.add_child(_section_header("ÉQUIPEMENT"))
	equip_box = VBoxContainer.new()
	equip_box.add_theme_constant_override("separation", 6)
	v.add_child(equip_box)

	v.add_child(_section_header("ARTEFACTS"))
	artifact_box = VBoxContainer.new()
	artifact_box.add_theme_constant_override("separation", 6)
	v.add_child(artifact_box)

func _section_header(txt: String) -> Control:
	var l := Label.new()
	l.text = "— %s —" % txt
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.55, 0.8, 1.0))
	return l

func _make_stat_row(grid: GridContainer, key: String, name: String) -> void:
	var n := Label.new()
	n.text = name
	n.add_theme_font_size_override("font_size", 14)
	n.add_theme_color_override("font_color", Color(0.7, 0.7, 0.78))
	grid.add_child(n)
	var val := Label.new()
	val.add_theme_font_size_override("font_size", 14)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(val)
	stat_labels[key] = val

func _build_log() -> void:
	var play_w := VIEW.x - SIDEBAR_W
	var log_panel := PanelContainer.new()
	log_panel.position = Vector2(12, VIEW.y - LOG_H)
	log_panel.size = Vector2(play_w - 24, LOG_H - 10)
	log_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.08, 0.07, 0.11)))
	hud_layer.add_child(log_panel)

	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.fit_content = true
	log_label.scroll_active = false
	log_label.custom_minimum_size = Vector2(play_w - 48, LOG_H - 32)
	log_panel.add_child(log_label)

# --- Écran HUB : Pied de la Tour (titre / boutique méta / choix du héros) -----
func show_hub(death_summary: String) -> void:
	state = State.HUB
	menu_layer.visible = true
	hud_layer.visible = false
	for c in menu_content.get_children():
		c.queue_free()

	_add_label("⛫  LES STRATES", 34, Color(0.7, 0.6, 1.0))
	_add_label("Roguelike — grimpe la tour, étage par étage (façon Aincrad).", 15, Color(0.7, 0.7, 0.8))
	_add_sep()

	if death_summary != "":
		_add_label(death_summary, 18, Color(1.0, 0.55, 0.45))
		_add_sep()

	_add_label("Éclats en banque : %d        Record : Étage %d" % [GameState.shards, GameState.best_floor],
		18, Color(1.0, 0.85, 0.35))

	_add_label("— Améliorations permanentes (dépense tes Éclats) —", 16, Color(0.6, 0.85, 1.0))
	for key in Data.UPGRADE_ORDER:
		var lvl: int = GameState.upgrade_level(key)
		var cost: int = Data.upgrade_cost(key, lvl)
		var info: Dictionary = Data.UPGRADES[key]
		var btn := Button.new()
		btn.text = "%s (niv. %d) — %s   [%d Éclats]" % [info["name"], lvl, info["desc"], cost]
		btn.disabled = not GameState.can_afford(key)
		btn.pressed.connect(_on_buy_upgrade.bind(key))
		menu_content.add_child(btn)

	_add_sep()
	_add_label("— Choisis ton héros —", 16, Color(0.6, 0.85, 1.0))
	for hero_id in Data.HERO_ORDER:
		var h: Dictionary = Data.HEROES[hero_id]
		var btn := Button.new()
		btn.text = "%s — PV %d | ATK %d | MAG %d | DEF %d | VIT %d | %s" % [
			h["name"], h["max_hp"] + GameState.bonus_hp(), h["atk"] + GameState.bonus_atk(),
			h["magic"], h["defense"], h["speed"], h["ability_name"]]
		btn.tooltip_text = h["lore"] + "\n" + h["ability_desc"]
		btn.pressed.connect(_on_choose_hero.bind(hero_id))
		menu_content.add_child(btn)

	_add_sep()
	_add_label("Déplacer : WASD / flèches / HJKL   •   Capacité : ESPACE   •   Attendre : .   •   Ramasse le butin en marchant dessus",
		13, Color(0.6, 0.6, 0.7))

func _on_buy_upgrade(key: String) -> void:
	if GameState.buy_upgrade(key):
		show_hub("")

func _on_choose_hero(hero_id: String) -> void:
	GameState.last_hero = hero_id
	GameState.save_game()
	start_run(hero_id)

# --- Démarrage d'un run -------------------------------------------------------
func start_run(hero_id: String) -> void:
	var h: Dictionary = Data.HEROES[hero_id]
	player = Entity.new()
	player.display_name = h["name"]
	player.glyph = h["glyph"]
	player.color = h["color"]
	player.faction = Entity.Faction.PLAYER
	player.base_max_hp = int(h["max_hp"]) + GameState.bonus_hp()
	player.base_atk = int(h["atk"]) + GameState.bonus_atk()
	player.base_magic = int(h["magic"])
	player.base_defense = int(h["defense"])
	player.base_speed = int(h["speed"])
	player.base_hp_regen = int(h["hp_regen"])
	player.ability_id = h["ability_id"]
	player.ability_range = int(h["ability_range"])
	player.ability_cd_max = int(h["ability_cd"])
	player.ability_cd = 0
	player.equipment = {}
	player.artifacts = []
	player.revive_used = false
	player.recompute_stats()
	player.hp = player.max_hp

	meta_ability_power = GameState.bonus_ability_power()
	floor_num = 1
	run_shards = 0
	messages.clear()
	loot.clear()
	add_message("[color=#9b8cff]Tu entres dans la Tour. Atteins l'escalier '>' pour monter.[/color]")
	menu_layer.visible = false
	hud_layer.visible = true
	state = State.PLAYING
	generate_floor()

func generate_floor() -> void:
	dungeon = Dungeon.new(MAP_W, MAP_H, rng)
	player.x = dungeon.start.x
	player.y = dungeon.start.y
	player.energy = Entity.ACTION_COST   # le joueur agit en premier

	enemies.clear()
	loot.clear()
	var occupied: Array = [dungeon.start, dungeon.stairs]
	var is_boss_floor: bool = (floor_num % BOSS_EVERY == 0)

	var count: int = min(3 + floor_num, 12)
	for p in dungeon.random_floor_tiles(count, rng, occupied):
		enemies.append(_make_enemy(_pick_enemy_def(), floor_num, p))
		occupied.append(p)

	if is_boss_floor:
		var boss_spots: Array = dungeon.random_floor_tiles(1, rng, occupied)
		if not boss_spots.is_empty():
			enemies.append(_make_boss(floor_num, boss_spots[0]))
			occupied.append(boss_spots[0])
		add_message("[color=#ff6464]⚠ Étage %d : un GARDIEN veille ici ![/color]" % floor_num)

	# Butin au sol : équipement + artefact occasionnel
	var loot_count: int = rng.randi_range(1, 3)
	for p in dungeon.random_floor_tiles(loot_count, rng, occupied):
		occupied.append(p)
		_spawn_loot(p)

	refresh()        # règle map_view.dungeon (nécessaire avant le centrage)
	_center_map()

func _pick_enemy_def() -> Dictionary:
	var pool: Array = []
	for def in Data.ENEMIES:
		if def["min_floor"] <= floor_num:
			pool.append(def)
	if pool.is_empty():
		pool = [Data.ENEMIES[0]]
	return pool[rng.randi_range(0, pool.size() - 1)]

func _make_enemy(def: Dictionary, floor: int, p: Vector2i) -> Entity:
	var e := Entity.new()
	var scale: float = 1.0 + float(floor - 1) * 0.12
	e.display_name = def["name"]
	e.glyph = def["glyph"]
	e.color = def["color"]
	e.faction = Entity.Faction.ENEMY
	e.max_hp = int(round(def["max_hp"] * scale))
	e.hp = e.max_hp
	e.atk = int(round(def["atk"] * scale))
	e.defense = int(def.get("defense", 0))
	e.speed = int(def.get("speed", 100))
	e.shard_value = def["shards"]
	e.x = p.x
	e.y = p.y
	e.energy = rng.randi_range(0, Entity.ACTION_COST - 1)
	return e

func _make_boss(floor: int, p: Vector2i) -> Entity:
	var def: Dictionary = Data.BOSS
	var scale: float = 1.0 + float(floor - 1) * 0.18
	var e := Entity.new()
	e.display_name = def["name"]
	e.glyph = def["glyph"]
	e.color = def["color"]
	e.faction = Entity.Faction.ENEMY
	e.is_boss = true
	e.max_hp = int(round(def["max_hp"] * scale))
	e.hp = e.max_hp
	e.atk = int(round(def["atk"] * scale))
	e.defense = int(def.get("defense", 0))
	e.speed = int(def.get("speed", 100))
	e.shard_value = def["shards"]
	e.x = p.x
	e.y = p.y
	e.energy = rng.randi_range(0, Entity.ACTION_COST - 1)
	return e

func _spawn_loot(p: Vector2i) -> void:
	var adef: Dictionary = {}
	if rng.randf() < 0.25:
		adef = _pick_artifact_def()
	if not adef.is_empty():
		loot.append({ "pos": p, "kind": "artifact", "glyph": Data.ARTIFACT_GLYPH,
			"color": adef["color"], "data": adef })
	else:
		var edef: Dictionary = _pick_equip_def()
		loot.append({ "pos": p, "kind": "equip", "glyph": Data.SLOT_GLYPH[edef["slot"]],
			"color": Data.SLOT_COLOR[edef["slot"]], "data": edef })

func _pick_equip_def() -> Dictionary:
	var pool: Array = []
	for def in Data.EQUIPMENT:
		if def["min_floor"] <= floor_num:
			pool.append(def)
	if pool.is_empty():
		pool = [Data.EQUIPMENT[0]]
	return pool[rng.randi_range(0, pool.size() - 1)]

func _pick_artifact_def() -> Dictionary:
	var pool: Array = []
	for def in Data.ARTIFACTS:
		if def["min_floor"] <= floor_num and not player.has_artifact(def["id"]):
			pool.append(def)
	if pool.is_empty():
		return {}
	return pool[rng.randi_range(0, pool.size() - 1)]

func _enemy_positions() -> Array:
	var arr: Array = []
	for e in enemies:
		arr.append(e.pos())
	return arr

func _center_map() -> void:
	var gsize: Vector2 = map_view.grid_pixel_size()
	var play_w: float = VIEW.x - SIDEBAR_W
	var play_h: float = VIEW.y - LOG_H
	map_view.position = Vector2(
		round((play_w - gsize.x) * 0.5),
		round((play_h - gsize.y) * 0.5) + 8
	)

# --- Entrées clavier ----------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if state != State.PLAYING:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_W, KEY_UP, KEY_K:
			try_move(0, -1)
		KEY_S, KEY_DOWN, KEY_J:
			try_move(0, 1)
		KEY_A, KEY_LEFT, KEY_H:
			try_move(-1, 0)
		KEY_D, KEY_RIGHT, KEY_L:
			try_move(1, 0)
		KEY_PERIOD, KEY_KP_5:
			pass_turn()
		KEY_SPACE, KEY_E:
			use_ability()

# --- Actions du joueur --------------------------------------------------------
func try_move(dx: int, dy: int) -> void:
	if state != State.PLAYING:
		return
	var nx: int = player.x + dx
	var ny: int = player.y + dy
	var target: Entity = enemy_at(nx, ny)
	if target != null:
		_player_attack(target, player.atk, "Tu frappes")
		_player_acted()
	elif dungeon.is_walkable(nx, ny):
		player.x = nx
		player.y = ny
		if player.pos() == dungeon.stairs:
			next_floor()
			return
		_pickup_loot_at(player.pos())
		_player_acted()
	# sinon : mur → aucun tour consommé

func pass_turn() -> void:
	if state != State.PLAYING:
		return
	_player_acted()

func use_ability() -> void:
	if state != State.PLAYING:
		return
	if not player.ability_ready():
		add_message("[color=#888888]Capacité en recharge (%d tour(s)).[/color]" % player.ability_cd)
		refresh()
		return
	var hit := false
	match player.ability_id:
		"whirl":
			hit = _do_whirl()
		"bolt":
			hit = _do_ranged(player.magic * 2 + player.atk + meta_ability_power, "[color=#7ab8ff]Éclair[/color] foudroie")
		"volley":
			hit = _do_ranged(int(player.atk * 1.5) + player.magic + meta_ability_power, "[color=#7aff8a]Flèche[/color] transperce")
	if not hit:
		add_message("[color=#888888]Aucune cible à portée.[/color]")
		refresh()
		return
	player.ability_cd = player.ability_cd_max
	_player_acted()

func _do_whirl() -> bool:
	var base: int = player.atk + player.magic + meta_ability_power
	var hit := false
	for e in enemies.duplicate():
		if e.is_alive() and _chebyshev(player.pos(), e.pos()) == 1:
			hit = true
			_player_attack(e, base, "[color=#ffd24a]Tourbillon[/color] frappe")
	return hit

func _do_ranged(base: int, verb: String) -> bool:
	var target: Entity = _nearest_enemy_in_range(player.ability_range)
	if target == null:
		return false
	_player_attack(target, base, verb)
	return true

func _nearest_enemy_in_range(rng_tiles: int) -> Entity:
	var best: Entity = null
	var best_d: int = 999999
	for e in enemies:
		if not e.is_alive():
			continue
		var d: int = _chebyshev(player.pos(), e.pos())
		if d <= rng_tiles and d < best_d:
			best_d = d
			best = e
	return best

# --- Combat -------------------------------------------------------------------
## Attaque du JOUEUR vers un ennemi : gère critique, défense, vol de vie.
func _player_attack(target: Entity, base_raw: int, verb: String) -> void:
	var raw: int = base_raw
	var crit: bool = player.has_artifact("crit") and rng.randf() < 0.25
	if crit:
		raw *= 2
	var dmg: int = max(1, raw - target.defense)
	var dealt: int = target.take_damage(dmg)
	var suffix: String = "  [color=#ffec5a]CRITIQUE![/color]" if crit else ""
	add_message("%s %s (-%d)%s" % [verb, target.display_name, dealt, suffix])
	if player.has_artifact("lifesteal") and dealt > 0:
		var healed: int = int(ceil(dealt * 0.3))
		player.heal(healed)
		add_message("[color=#ff7a8a]Vol de vie : +%d PV.[/color]" % healed)
	if not target.is_alive():
		on_enemy_killed(target)

## Attaque d'un ENNEMI vers le joueur : gère esquive, défense, épines, Phénix.
func _enemy_attack_player(attacker: Entity) -> void:
	if player.has_artifact("dodge") and rng.randf() < 0.2:
		add_message("[color=#b3a8e0]Tu esquives %s ![/color]" % attacker.display_name)
		return
	var dmg: int = max(1, attacker.atk - player.defense)
	player.take_damage(dmg)
	add_message("[color=#ff8a8a]%s te frappe (-%d).[/color]" % [attacker.display_name, dmg])
	if player.has_artifact("thorns"):
		var refl: int = max(1, int(ceil(player.defense * 0.5)) + 2)
		var d2: int = attacker.take_damage(refl)
		add_message("[color=#cdd66a]Épines : %s subit %d.[/color]" % [attacker.display_name, d2])
		if not attacker.is_alive():
			on_enemy_killed(attacker)
	_check_revive()

func _check_revive() -> void:
	if player.hp <= 0 and player.has_artifact("phoenix") and not player.revive_used:
		player.revive_used = true
		player.hp = max(1, int(player.max_hp * 0.5))
		add_message("[color=#ffd24a]✦ La Plume de Phénix te ramène à la vie ![/color]")

func on_enemy_killed(e: Entity) -> void:
	if not enemies.has(e):
		return
	run_shards += e.shard_value
	enemies.erase(e)
	if e.is_boss:
		add_message("[color=#ffd24a]★ Le Gardien tombe ! +%d Éclats. La voie est libre.[/color]" % e.shard_value)
	else:
		add_message("%s meurt. [color=#ffd24a]+%d Éclats[/color]." % [e.display_name, e.shard_value])

# --- Butin & équipement -------------------------------------------------------
func _pickup_loot_at(p: Vector2i) -> void:
	for item in loot.duplicate():
		if item["pos"] == p:
			loot.erase(item)
			if item["kind"] == "equip":
				_acquire_equipment(item["data"])
			else:
				_acquire_artifact(item["data"])

func _acquire_equipment(def: Dictionary) -> void:
	var slot: String = def["slot"]
	var new_power: int = _equip_power(def)
	if player.equipment.has(slot):
		var cur: Dictionary = player.equipment[slot]
		if _equip_power(cur) >= new_power:
			run_shards += int(def.get("salvage", 1))
			add_message("Tu gardes %s ; %s recyclé (+%d Éclats)." % [cur["name"], def["name"], int(def.get("salvage", 1))])
			return
		run_shards += int(cur.get("salvage", 1))
		add_message("Tu remplaces %s (+%d Éclats)." % [cur["name"], int(cur.get("salvage", 1))])
	player.equipment[slot] = def
	player.recompute_stats()
	add_message("[color=#9fe0ff]Équipé : %s [%s] — %s[/color]" % [
		def["name"], Data.SLOT_NAMES[slot], Data.bonus_summary(def["bonus"])])

func _equip_power(def: Dictionary) -> int:
	var s: int = 0
	for k in def["bonus"]:
		s += int(def["bonus"][k])
	return s

func _acquire_artifact(def: Dictionary) -> void:
	if player.has_artifact(def["id"]):
		run_shards += 5
		add_message("Artefact %s déjà actif (+5 Éclats)." % def["name"])
		return
	player.artifacts.append(def)
	player.recompute_stats()
	add_message("[color=#f0b8ff]✦ Artefact : %s — %s[/color]" % [def["name"], def["desc"]])

# --- Boucle de tour à énergie -------------------------------------------------
func _player_acted() -> void:
	player.energy -= Entity.ACTION_COST
	_apply_regen(player)
	player.tick_cooldown()
	if not player.is_alive():
		_check_revive()
	if not player.is_alive():
		game_over()
		return
	advance_world()
	if state != State.PLAYING:
		return
	refresh()

## Laisse agir les autres acteurs (selon leur vitesse) jusqu'au prochain tour du joueur.
func advance_world() -> void:
	var safety := 0
	while true:
		safety += 1
		if safety > 10000:
			return
		if player.energy >= Entity.ACTION_COST:
			return
		var ready: Array = []
		for e in enemies:
			if e.is_alive() and e.energy >= Entity.ACTION_COST:
				ready.append(e)
		if ready.is_empty():
			player.energy += player.speed
			for e in enemies:
				if e.is_alive():
					e.energy += e.speed
			continue
		for e in ready:
			if not e.is_alive():
				continue
			e.energy -= Entity.ACTION_COST
			_apply_regen(e)
			_enemy_act(e)
			if not player.is_alive():
				game_over()
				return

func _apply_regen(e: Entity) -> void:
	if e.hp_regen > 0 and e.is_alive():
		e.heal(e.hp_regen)

func _enemy_act(e: Entity) -> void:
	if _manhattan(e.pos(), player.pos()) == 1:
		_enemy_attack_player(e)
		return
	var dx: int = signi(player.x - e.x)
	var dy: int = signi(player.y - e.y)
	var tries: Array = []
	if abs(player.x - e.x) >= abs(player.y - e.y):
		tries = [Vector2i(dx, 0), Vector2i(0, dy)]
	else:
		tries = [Vector2i(0, dy), Vector2i(dx, 0)]
	for t in tries:
		if t == Vector2i.ZERO:
			continue
		var nx: int = e.x + t.x
		var ny: int = e.y + t.y
		if dungeon.is_walkable(nx, ny) and enemy_at(nx, ny) == null and player.pos() != Vector2i(nx, ny):
			e.x = nx
			e.y = ny
			return

func next_floor() -> void:
	floor_num += 1
	GameState.record_floor(floor_num)
	var healed: int = int(round(player.max_hp * 0.2))
	player.heal(healed)
	add_message("[color=#9b8cff]Tu gravis l'étage %d. (+%d PV en récupérant ton souffle)[/color]" % [floor_num, healed])
	generate_floor()

func game_over() -> void:
	GameState.add_shards(run_shards)
	GameState.record_floor(floor_num)
	state = State.DEAD
	var summary := "💀 Tu es tombé à l'Étage %d. Butin du run : %d Éclats (ajoutés à la banque)." % [floor_num, run_shards]
	show_hub(summary)

# --- Rendu / HUD --------------------------------------------------------------
func refresh() -> void:
	map_view.refresh(dungeon, [player] + enemies, loot)
	_update_hud()
	_update_log()

func _update_hud() -> void:
	sb_floor.text = "Étage %d" % floor_num
	sb_hero.text = player.display_name
	sb_hero.add_theme_color_override("font_color", player.color)
	hp_bar.max_value = max(1, player.max_hp)
	hp_bar.value = clampi(player.hp, 0, player.max_hp)
	hp_text.text = "PV  %d / %d" % [player.hp, player.max_hp]

	stat_labels["atk"].text = str(player.atk)
	stat_labels["magic"].text = str(player.magic)
	stat_labels["defense"].text = str(player.defense)
	stat_labels["speed"].text = str(player.speed)
	stat_labels["hp_regen"].text = str(player.hp_regen)
	stat_labels["run_shards"].text = str(run_shards)
	stat_labels["bank"].text = str(GameState.shards)

	var h: Dictionary = Data.HEROES[GameState.last_hero]
	if player.ability_ready():
		sb_ability.text = "%s\n[ESPACE] — PRÊTE" % h["ability_name"]
		sb_ability.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	else:
		sb_ability.text = "%s\n[ESPACE] — recharge %d tour(s)" % [h["ability_name"], player.ability_cd]
		sb_ability.add_theme_color_override("font_color", Color(0.85, 0.85, 0.5))

	_rebuild_equip()
	_rebuild_artifacts()

func _rebuild_equip() -> void:
	for c in equip_box.get_children():
		c.queue_free()
	for slot in Data.SLOTS:
		var head := Label.new()
		head.text = "%s %s" % [Data.SLOT_GLYPH[slot], Data.SLOT_NAMES[slot]]
		head.add_theme_font_size_override("font_size", 13)
		head.add_theme_color_override("font_color", Data.SLOT_COLOR[slot])
		equip_box.add_child(head)
		var line := Label.new()
		line.add_theme_font_size_override("font_size", 14)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(SIDEBAR_W - 60, 0)
		if player.equipment.has(slot):
			var it: Dictionary = player.equipment[slot]
			line.text = "%s  (%s)" % [it["name"], Data.bonus_summary(it["bonus"])]
			line.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
		else:
			line.text = "— vide —"
			line.add_theme_color_override("font_color", Color(0.5, 0.5, 0.58))
		equip_box.add_child(line)

func _rebuild_artifacts() -> void:
	for c in artifact_box.get_children():
		c.queue_free()
	if player.artifacts.is_empty():
		var none := Label.new()
		none.text = "— aucun —"
		none.add_theme_font_size_override("font_size", 14)
		none.add_theme_color_override("font_color", Color(0.5, 0.5, 0.58))
		artifact_box.add_child(none)
		return
	for a in player.artifacts:
		var name_l := Label.new()
		name_l.text = "✦ " + str(a.get("name", "?"))
		name_l.add_theme_font_size_override("font_size", 14)
		name_l.add_theme_color_override("font_color", Color(0.95, 0.75, 1.0))
		artifact_box.add_child(name_l)
		var desc_l := Label.new()
		desc_l.text = str(a.get("desc", ""))
		desc_l.add_theme_font_size_override("font_size", 12)
		desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_l.custom_minimum_size = Vector2(SIDEBAR_W - 60, 0)
		desc_l.add_theme_color_override("font_color", Color(0.65, 0.65, 0.72))
		artifact_box.add_child(desc_l)

func _update_log() -> void:
	log_label.text = "\n".join(messages)

func add_message(msg: String) -> void:
	messages.append(msg)
	while messages.size() > MAX_LOG:
		messages.pop_front()

# --- Utilitaires --------------------------------------------------------------
func enemy_at(x: int, y: int) -> Entity:
	for e in enemies:
		if e.is_alive() and e.x == x and e.y == y:
			return e
	return null

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return max(abs(a.x - b.x), abs(a.y - b.y))

func _add_label(txt: String, fsize: int, col: Color) -> void:
	var l := Label.new()
	l.text = txt
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	menu_content.add_child(l)

func _add_sep() -> void:
	menu_content.add_child(HSeparator.new())
