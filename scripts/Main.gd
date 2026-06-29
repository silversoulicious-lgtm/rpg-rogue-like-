## Coordinateur du jeu : état, génération d'étage, combat tour-par-tour, IA,
## capacités, butin/inventaire, montée de niveau. Tout l'AFFICHAGE est délégué
## à Hud (scripts/Hud.gd). "Les Strates" — roguelike d'ascension de tour.
extends Node2D

enum State { TITLE, LOADOUT, META, MAP, PLAYING, CHOICE, LEVELUP, INVENTORY, GAMEOVER }

const MAX_LOG := 8
const INV_CAP := 16

var state: int = State.TITLE
var rng := RandomNumberGenerator.new()

# Run en cours
var player: Entity = null
var enemies: Array = []          # Array[Entity]
var loot: Array = []             # Array[dict] : { pos, kind, glyph, sprite, color, data }
var dungeon: Dungeon = null
var floor_num: int = 1
var run_shards: int = 0
var messages: Array = []
var inventory: Array = []        # sac : Array[item dict]
var pending_levelups: int = 0

# Carte de strate à embranchements
var run_map: RunMap = null
var map_act: int = 0
var map_pos: Vector2i = Vector2i(-1, -1)   # (rangée, idx) ; -1 = pas encore entré
var current_node_type: String = "combat"
var shop_stock: Array = []
var current_event: Dictionary = {}
var first_strike_used: bool = false   # pour le proc d'objet unique "premier_coup"

# Compétences (Phase 2)
var known_skills: Array = []          # ids de compétences droppées et apprises (hors bases)
var last_dir: Vector2i = Vector2i(1, 0)   # dernière direction de déplacement (visée auto)
const SKILL_DROP_CHANCE := 0.06       # chance qu'un monstre lâche une compétence
const LEGENDARY_CHANCE := 0.025       # chance qu'un monstre soit légendaire (lâche un pouvoir)

# Statistiques du run en cours (pour le journal de fin de run)
var run_kills: int = 0
var run_best_hit: int = 0
var run_best_item: Dictionary = {}

var map_view: Node2D
var hud                          # instance de Hud (scripts/Hud.gd)

func _ready() -> void:
	rng.randomize()
	map_view = Node2D.new()
	map_view.set_script(load("res://scripts/MapView.gd"))
	add_child(map_view)
	hud = Node.new()
	hud.set_script(load("res://scripts/Hud.gd"))
	add_child(hud)
	hud.setup(self)
	map_view.view_size = hud.play_area()
	return_to_title()

# --- Flux d'écrans ------------------------------------------------------------
## Écran-titre (point d'entrée du jeu).
func return_to_title() -> void:
	state = State.TITLE
	hud.show_title()

## Écran de loadout : choix de l'arme de départ (fiches détaillées).
func open_loadout() -> void:
	state = State.LOADOUT
	hud.show_loadout()

## Sanctuaire : méta-progression entre les runs.
func open_meta() -> void:
	state = State.META
	hud.show_meta()

func quit_game() -> void:
	get_tree().quit()

## Lance un run avec l'arme de départ choisie (loadout : "melee"/"ranged"/"magic").
func choose_loadout(loadout_id: String) -> void:
	GameState.last_loadout = loadout_id
	GameState.save_game()
	start_run(loadout_id)

func start_run(loadout_id: String = "melee") -> void:
	if not Data.WEAPON_TYPES.has(loadout_id):
		loadout_id = "melee"
	var h: Dictionary = Data.HEROINE
	player = Entity.new()
	player.display_name = h["name"]
	player.glyph = h["glyph"]
	player.sprite = h["sprite"]
	player.color = h["color"]
	player.faction = Entity.Faction.PLAYER
	player.base_max_hp = int(h["max_hp"]) + GameState.bonus_hp()
	player.base_atk = int(h["atk"]) + GameState.bonus_atk()
	player.base_magic = int(h["magic"])
	player.base_defense = int(h["defense"])
	player.base_speed = int(h["speed"])
	player.base_hp_regen = int(h["hp_regen"])
	player.base_ability_power = GameState.bonus_ability_power()
	player.base_ability_cd = 0          # la recharge vient de l'arme équipée
	player.base_vision = Data.BASE_VISION
	player.ability_cd = 0
	player.equipment = { "arme": Data.make_starter_weapon(loadout_id) }
	player.active_skill_id = Data.WEAPON_TYPE_BASE_SKILL[loadout_id]
	player.artifacts = []
	player.powers = []
	player.talents = []
	player.level = 1
	player.xp = 0
	player.revives_used = 0
	known_skills.clear()
	player.recompute_stats()
	player.hp = player.max_hp

	floor_num = 1
	run_shards = GameState.bonus_start_shards()
	run_kills = 0
	run_best_hit = 0
	run_best_item = {}
	pending_levelups = 0
	messages.clear()
	loot.clear()
	inventory.clear()
	_grant_starting_bonuses()
	add_message("[color=#9b8cff]Tu entres dans la Tour. Trace ta voie vers le Gardien.[/color]")
	map_act = 0
	_start_act()

## Applique les bonus de départ achetés en méta-progression (Héritage/Instinct).
func _grant_starting_bonuses() -> void:
	if run_shards > 0:
		add_message("[color=#ffd24a]Fortune : tu démarres avec %d Éclats.[/color]" % run_shards)
	for i in GameState.start_artifacts():
		var a: Dictionary = _pick_any_artifact()
		if not a.is_empty():
			player.artifacts.append(a)
			add_message("[color=#f0b8ff]✦ Héritage : %s[/color]" % a["name"])
	for i in GameState.start_talents():
		var t: Dictionary = Data.TALENTS[rng.randi_range(0, Data.TALENTS.size() - 1)]
		player.talents.append(t)
		add_message("[color=#9fff9f]Instinct : talent de départ — %s.[/color]" % t["name"])
	player.recompute_stats()
	player.hp = player.max_hp

func _pick_any_artifact() -> Dictionary:
	var pool: Array = []
	for def in Data.ARTIFACTS:
		if not player.has_artifact(def["id"]):
			pool.append(def)
	if pool.is_empty():
		return {}
	return pool[rng.randi_range(0, pool.size() - 1)]

# --- Carte de strate ----------------------------------------------------------
func _start_act() -> void:
	run_map = RunMap.new(map_act, rng)
	map_pos = Vector2i(-1, -1)
	enemies.clear()
	dungeon = null
	state = State.MAP
	refresh()
	hud.show_map(run_map, map_pos)

func reachable_indices() -> Array:
	var next_row: int = map_pos.x + 1
	if run_map == null or next_row >= run_map.nodes.size():
		return []
	if map_pos.x < 0:
		return range(run_map.nodes[0].size())
	return run_map.nodes[map_pos.x][map_pos.y]["edges"]

func choose_map_node(idx: int) -> void:
	var next_row: int = map_pos.x + 1
	if next_row >= run_map.nodes.size() or not reachable_indices().has(idx):
		return
	map_pos = Vector2i(next_row, idx)
	_enter_node(run_map.nodes[next_row][idx])

func _enter_node(node: Dictionary) -> void:
	match node["type"]:
		"shop":
			open_shop()
		"event":
			open_event()
		"rest":
			open_rest()
		_:
			current_node_type = node["type"]
			floor_num += 1
			state = State.PLAYING
			hud.hide_map()
			hud.show_game()
			generate_floor(current_node_type)

func _node_cleared() -> void:
	var was_boss: bool = current_node_type == "boss"
	var healed: int = int(round(player.max_hp * 0.2))
	player.heal(healed)
	if was_boss:
		map_act += 1
		add_message("[color=#9b8cff]★ Strate franchie ! Tu pénètres dans la strate %d.[/color]" % (map_act + 1))
		_start_act()
	else:
		add_message("[color=#9b8cff]Voie dégagée (+%d PV). Choisis ta route.[/color]" % healed)
		_back_to_map()

func _back_to_map() -> void:
	state = State.MAP
	refresh()
	hud.show_map(run_map, map_pos)

func _boss_alive() -> bool:
	for e in enemies:
		if e.is_boss and e.is_alive():
			return true
	return false

# --- Génération d'un combat (combat / élite / boss) ---------------------------
func generate_floor(node_type: String = "combat") -> void:
	first_strike_used = false
	player.clear_statuses()
	var msize: Vector2i = Data.random_map_size(rng)
	dungeon = Dungeon.new(msize.x, msize.y, rng, Data.biome_for_floor(floor_num))
	player.x = dungeon.start.x
	player.y = dungeon.start.y
	player.energy = Entity.ACTION_COST   # le joueur agit en premier
	dungeon.reveal(player.pos(), player.vision)

	enemies.clear()
	loot.clear()
	var occupied: Array = [dungeon.start, dungeon.stairs]
	var is_elite: bool = node_type == "elite"
	var is_boss: bool = node_type == "boss"

	# Le peuplement s'adapte à la taille de la carte (exploration jamais vide).
	var area: int = dungeon.width * dungeon.height
	var count: int = clampi(3 + floor_num + int(area / 2200), 5, 30)
	if is_elite:
		count = mini(count + 3, 34)
	for p in dungeon.random_floor_tiles(count, rng, occupied):
		var e: Entity = _make_enemy(_pick_enemy_def(), floor_num, p)
		if is_elite:
			e.max_hp = int(e.max_hp * 1.25)
			e.hp = e.max_hp
			e.atk = int(e.atk * 1.2)
		elif not is_boss and rng.randf() < LEGENDARY_CHANCE:
			e.is_legendary = true
			e.display_name = "Légendaire : " + e.display_name
			e.max_hp = int(e.max_hp * 1.8)
			e.hp = e.max_hp
			e.atk = int(e.atk * 1.4)
			e.shard_value = e.shard_value * 2
		enemies.append(e)
		occupied.append(p)

	if is_boss:
		var boss_spots: Array = dungeon.random_floor_tiles(1, rng, occupied)
		if not boss_spots.is_empty():
			enemies.append(_make_enemy(Data.BOSS, floor_num, boss_spots[0], true))
			occupied.append(boss_spots[0])
		add_message("[color=#ff6464]⚠ Le GARDIEN de la strate t'attend ! Vaincs-le pour ouvrir l'escalier.[/color]")
	elif is_elite:
		add_message("[color=#ff9a64]☠ Salle d'élite : ennemis renforcés, meilleur butin.[/color]")

	var loot_count: int = mini(rng.randi_range(1, 3) + int(area / 9000) + (1 if is_elite else 0), 14)
	for p in dungeon.random_floor_tiles(loot_count, rng, occupied):
		occupied.append(p)
		_spawn_loot(p, is_elite)

	refresh()        # règle map_view.dungeon, le brouillard et la caméra

func _pick_enemy_def() -> Dictionary:
	var pool: Array = []
	for def in Data.ENEMIES:
		if def["min_floor"] <= floor_num:
			pool.append(def)
	if pool.is_empty():
		pool = [Data.ENEMIES[0]]
	return pool[rng.randi_range(0, pool.size() - 1)]

## Crée un ennemi (ou un boss si is_boss) à partir d'une définition, scalé par l'étage.
func _make_enemy(def: Dictionary, floor: int, p: Vector2i, is_boss: bool = false) -> Entity:
	var e := Entity.new()
	var scale: float = 1.0 + float(floor - 1) * (0.18 if is_boss else 0.12)
	e.display_name = def["name"]
	e.glyph = def["glyph"]
	e.sprite = def.get("sprite", "boss" if is_boss else "")
	e.color = def["color"]
	e.faction = Entity.Faction.ENEMY
	e.is_boss = is_boss
	e.max_hp = int(round(def["max_hp"] * scale))
	e.hp = e.max_hp
	e.atk = int(round(def["atk"] * scale))
	e.defense = int(def.get("defense", 0))
	e.speed = int(def.get("speed", 100))
	e.shard_value = def["shards"]
	e.x = p.x
	e.y = p.y
	e.energy = rng.randi_range(0, Entity.ACTION_COST - 1)
	if is_boss:
		e.hp_regen = 3          # le Gardien se régénère : combat d'usure distinctif
		e.enraged = false
	return e

func _spawn_loot(p: Vector2i, force_good: bool = false) -> void:
	var roll: float = rng.randf()
	var adef: Dictionary = {}
	if roll < 0.18 and not force_good:
		adef = _pick_artifact_def()
	if not adef.is_empty():
		loot.append({ "pos": p, "kind": "artifact", "glyph": Data.ARTIFACT_GLYPH,
			"sprite": "artifact", "color": adef["color"], "data": adef })
	elif roll < 0.42 and not force_good:
		var c: Dictionary = Data.generate_consumable(floor_num, rng)
		loot.append({ "pos": p, "kind": "consumable", "glyph": "!",
			"sprite": "potion", "color": c["color"], "data": c })
	else:
		# l'élite force un meilleur objet (étage virtuel plus élevé -> raretés boostées)
		var lvl: int = floor_num + (4 if force_good else 0)
		var slot: String = Data.SLOTS[rng.randi_range(0, Data.SLOTS.size() - 1)]
		var item: Dictionary = Data.generate_item(slot, lvl, rng)
		loot.append({ "pos": p, "kind": "equip", "glyph": Data.SLOT_GLYPH[slot],
			"sprite": slot, "color": item["rarity_color"], "data": item })

func _pick_artifact_def() -> Dictionary:
	var pool: Array = []
	for def in Data.ARTIFACTS:
		if def["min_floor"] <= floor_num and not player.has_artifact(def["id"]):
			pool.append(def)
	if pool.is_empty():
		return {}
	return pool[rng.randi_range(0, pool.size() - 1)]

## Caméra : suit le joueur (centré), bornée aux limites de la carte.
func _update_camera() -> void:
	if dungeon == null or player == null:
		return
	var pa: Vector2 = hud.play_area()
	var cell: int = map_view.CELL
	var map_px: float = float(dungeon.width * cell)
	var map_py: float = float(dungeon.height * cell)
	var px: float = player.x * cell + cell * 0.5
	var py: float = player.y * cell + cell * 0.5
	var cam_x: float = px - pa.x * 0.5
	var cam_y: float = py - pa.y * 0.5
	if map_px > pa.x:
		cam_x = clampf(cam_x, 0.0, map_px - pa.x)
	else:
		cam_x = (map_px - pa.x) * 0.5
	if map_py > pa.y:
		cam_y = clampf(cam_y, 0.0, map_py - pa.y)
	else:
		cam_y = (map_py - pa.y) * 0.5
	map_view.position = Vector2(round(-cam_x), round(-cam_y))

# --- Entrées clavier ----------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = event.keycode
	if state == State.INVENTORY:
		if k == KEY_I or k == KEY_ESCAPE:
			close_inventory()
		return
	# Navigation clavier dans les écrans de menu (Échap = revenir en arrière).
	if state == State.LOADOUT or state == State.META:
		if k == KEY_ESCAPE:
			return_to_title()
		return
	if state == State.GAMEOVER:
		if k == KEY_ESCAPE or k == KEY_ENTER or k == KEY_KP_ENTER:
			return_to_title()
		return
	if state != State.PLAYING:
		return
	match k:
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
		KEY_I:
			open_inventory()

# --- Actions du joueur --------------------------------------------------------
## Si l'héroïne est paralysée, toute action lui fait perdre son tour.
func _player_stunned() -> bool:
	if player != null and player.has_status("stun"):
		add_message("[color=#b3a8e0]Tu es paralysée — tour perdu ![/color]")
		_player_acted()
		return true
	return false

func try_move(dx: int, dy: int) -> void:
	if state != State.PLAYING:
		return
	if _player_stunned():
		return
	var nx: int = player.x + dx
	var ny: int = player.y + dy
	var target: Entity = enemy_at(nx, ny)
	if target != null:
		_player_attack(target, player.atk, "Tu frappes")
		_player_acted()
	elif dungeon.is_walkable(nx, ny):
		if Vector2i(nx, ny) == dungeon.stairs:
			if current_node_type == "boss" and _boss_alive():
				add_message("[color=#ff8a8a]Vaincs le Gardien avant de franchir l'escalier ![/color]")
				refresh()
				return
			player.x = nx
			player.y = ny
			_node_cleared()
			return
		player.x = nx
		player.y = ny
		last_dir = Vector2i(dx, dy)
		_pickup_loot_at(player.pos())
		_player_acted()
	# sinon : mur → aucun tour consommé

func pass_turn() -> void:
	if state != State.PLAYING:
		return
	if _player_stunned():
		return
	_player_acted()

func use_ability() -> void:
	if state != State.PLAYING:
		return
	if _player_stunned():
		return
	if player.ability_id == "" or not Data.SKILLS.has(player.ability_id):
		add_message("[color=#888888]Aucune compétence active.[/color]")
		refresh()
		return
	if not player.ability_ready():
		add_message("[color=#888888]Compétence en recharge (%d tour(s)).[/color]" % player.ability_cd)
		refresh()
		return
	if not _cast_skill(Data.SKILLS[player.ability_id]):
		add_message("[color=#888888]Aucune cible à portée.[/color]")
		refresh()
		return
	player.ability_cd = player.ability_cd_max
	_player_acted()

## Dégâts de base d'une compétence selon le type d'arme, × multiplicateur "power".
func _skill_damage(skill: Dictionary) -> int:
	var b: int
	match String(skill.get("wtype", "melee")):
		"ranged": b = int(round(player.atk * 1.3)) + player.ability_power
		"magic":  b = player.magic * 2 + player.ability_power
		_:        b = player.atk + player.ability_power
	return maxi(1, int(round(float(b) * float(skill.get("power", 1.0)))))

## Direction cardinale (axe dominant) du joueur vers une case (visée auto).
func _cardinal_to(target: Vector2i) -> Vector2i:
	var dx: int = target.x - player.x
	var dy: int = target.y - player.y
	if abs(dx) >= abs(dy):
		return Vector2i(signi(dx), 0) if dx != 0 else last_dir
	return Vector2i(0, signi(dy))

## Exécute une compétence (data-driven). Renvoie false si aucune cible/effet.
func _cast_skill(skill: Dictionary) -> bool:
	var dmg: int = _skill_damage(skill)
	var name: String = String(skill.get("name", "Compétence"))
	var rng_tiles: int = int(skill.get("range", 1))
	match String(skill.get("effect", "")):
		"aoe":
			return aoe_attack(player.pos(), int(skill.get("radius", 1)), dmg, "%s frappe" % name) > 0
		"single":
			var t: Entity = _nearest_enemy_in_range(rng_tiles)
			if t == null: return false
			_player_attack(t, dmg, "%s touche" % name)
			return true
		"melee_multi", "ranged_multi":
			var tm: Entity = _nearest_enemy_in_range(rng_tiles)
			if tm == null: return false
			for i in int(skill.get("hits", 2)):
				if tm.is_alive():
					_player_attack(tm, dmg, "%s touche" % name)
			return true
		"true_strike":
			var ts: Entity = _nearest_enemy_in_range(rng_tiles)
			if ts == null: return false
			_player_attack(ts, dmg, "%s transperce" % name, true)
			return true
		"vampiric":
			var tv: Entity = _nearest_enemy_in_range(rng_tiles)
			if tv == null: return false
			var before: int = tv.hp
			_player_attack(tv, dmg, "%s saigne" % name)
			var dealt: int = before - tv.hp
			var healed: int = int(ceil(float(dealt) * float(skill.get("heal_pct", 0.5))))
			if healed > 0:
				player.heal(healed)
				add_message("[color=#ff7a8a]%s : +%d PV.[/color]" % [name, healed])
			return true
		"dash_strike":
			var td: Entity = _nearest_enemy_in_range(99)
			if td == null: return false
			dash(_cardinal_to(td.pos()), int(skill.get("dash", 3)))
			var adj: Entity = _nearest_enemy_in_range(1)
			if adj != null:
				_player_attack(adj, dmg, "%s fend" % name)
			return true
		"explosive":
			var te: Entity = _nearest_enemy_in_range(rng_tiles)
			if te == null: return false
			var center: Vector2i = te.pos()
			_player_attack(te, dmg, "%s touche" % name)
			aoe_attack(center, int(skill.get("radius", 1)), int(round(dmg * 0.7)), "%s explose" % name)
			return true
		"pierce":
			var tp: Entity = _nearest_enemy_in_range(rng_tiles)
			if tp == null: return false
			return pierce_attack(player.pos(), _cardinal_to(tp.pos()), dmg, "%s transperce" % name, rng_tiles) > 0
		"bounce", "chain":
			var tb: Entity = _nearest_enemy_in_range(rng_tiles)
			if tb == null: return false
			return bounce_attack(tb, dmg, int(skill.get("bounces", 3)), "%s rebondit" % name, 0.85, maxi(rng_tiles, 6)) > 0
		"status_shot":
			var tst: Entity = _nearest_enemy_in_range(rng_tiles)
			if tst == null: return false
			_player_attack(tst, dmg, "%s touche" % name)
			if tst.is_alive():
				_apply_skill_status(tst, skill, dmg)
			return true
	return false

func _apply_skill_status(target: Entity, skill: Dictionary, dmg: int) -> void:
	var turns: int = int(skill.get("turns", 2))
	match String(skill.get("status", "")):
		"slow":
			apply_slow(target, turns, float(skill.get("val", 0.4)))
			add_message("[color=#9fdfff]%s est ralenti.[/color]" % target.display_name)
		"stun":
			apply_stun(target, turns)
			add_message("[color=#cdb8ff]%s est paralysé.[/color]" % target.display_name)
		"burn":
			apply_burn(target, turns, maxf(1.0, round(float(dmg) * float(skill.get("val", 0.3)))))
			add_message("[color=#ff9a5a]%s prend feu.[/color]" % target.display_name)
		"poison":
			apply_poison(target, turns, maxf(1.0, round(float(dmg) * float(skill.get("val", 0.3)))))
			add_message("[color=#9fdf6a]%s est empoisonné.[/color]" % target.display_name)

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

# --- Primitives de combat (briques réutilisées par les compétences/pouvoirs) --
## Zone : frappe tous les ennemis vivants dans le rayon (Chebyshev) du centre.
func aoe_attack(center: Vector2i, radius: int, base: int, verb: String) -> int:
	var hits := 0
	for e in enemies.duplicate():
		if e.is_alive() and _chebyshev(center, e.pos()) <= radius:
			_player_attack(e, base, verb)
			hits += 1
	return hits

## Transpercement : depuis `from`, avance selon `dir` et frappe tous les ennemis
## alignés jusqu'à un obstacle/bord (ou max_range cases).
func pierce_attack(from: Vector2i, dir: Vector2i, base: int, verb: String, max_range: int = 12) -> int:
	var hits := 0
	var p: Vector2i = from
	for i in max_range:
		p += dir
		if not dungeon.is_walkable(p.x, p.y):
			break
		var e: Entity = enemy_at(p.x, p.y)
		if e != null and e.is_alive():
			_player_attack(e, base, verb)
			hits += 1
	return hits

## Rebond / chaîne : frappe une 1re cible puis saute vers l'ennemi vivant le plus
## proche non encore touché (jusqu'à `bounces` sauts), avec atténuation `falloff`.
func bounce_attack(first: Entity, base: int, bounces: int, verb: String, falloff: float = 0.85, jump_range: int = 6) -> int:
	if first == null or not first.is_alive():
		return 0
	var hit_ids := {}
	var current: Entity = first
	var dmg: int = base
	var hits := 0
	for i in bounces + 1:
		if current == null or not current.is_alive():
			break
		_player_attack(current, dmg, verb)
		hit_ids[current.get_instance_id()] = true
		hits += 1
		dmg = max(1, int(round(dmg * falloff)))
		current = _nearest_enemy_excluding(current.pos(), jump_range, hit_ids)
	return hits

## Dash : déplace le joueur de `distance` cases dans `dir`, s'arrêtant avant un
## obstacle ou un ennemi. Renvoie le nombre de cases parcourues.
func dash(dir: Vector2i, distance: int) -> int:
	var moved := 0
	for i in distance:
		var nx: int = player.x + dir.x
		var ny: int = player.y + dir.y
		if not dungeon.is_walkable(nx, ny) or enemy_at(nx, ny) != null or Vector2i(nx, ny) == dungeon.stairs:
			break
		player.x = nx
		player.y = ny
		moved += 1
	if moved > 0:
		_pickup_loot_at(player.pos())
	return moved

func _nearest_enemy_excluding(from: Vector2i, rng_tiles: int, exclude: Dictionary) -> Entity:
	var best: Entity = null
	var best_d: int = 999999
	for e in enemies:
		if not e.is_alive() or exclude.has(e.get_instance_id()):
			continue
		var d: int = _chebyshev(from, e.pos())
		if d <= rng_tiles and d < best_d:
			best_d = d
			best = e
	return best

# --- Statuts : application (utilisés par compétences/pouvoirs) -----------------
func apply_poison(target: Entity, turns: int, dmg_per_turn: float, max_stacks: int = 10) -> void:
	target.add_status("poison", turns, dmg_per_turn, max_stacks)

func apply_burn(target: Entity, turns: int, dmg_per_turn: float, max_stacks: int = 5) -> void:
	target.add_status("burn", turns, dmg_per_turn, max_stacks)

func apply_slow(target: Entity, turns: int, pct: float) -> void:
	target.add_status("slow", turns, pct)

func apply_stun(target: Entity, turns: int) -> void:
	target.add_status("stun", turns)

# --- Combat -------------------------------------------------------------------
## Attaque du JOUEUR vers un ennemi : gère critique, défense, vol de vie,
## et les procs d'objets uniques (exécution, frénésie, premier coup, frappe double).
func _player_attack(target: Entity, base_raw: int, verb: String, ignore_def: bool = false) -> void:
	var raw: float = float(base_raw)
	var is_execute := false
	if player.has_proc("frenesie") and player.hp <= player.max_hp * 0.4:
		raw *= 1.0 + player.proc_value("frenesie")
	if player.has_proc("execution") and target.hp <= target.max_hp * 0.25:
		raw *= 1.0 + player.proc_value("execution")
		is_execute = true
	var force_crit: bool = player.has_proc("premier_coup") and not first_strike_used
	first_strike_used = true
	var crit: bool = force_crit or rng.randf() < player.crit_chance
	if crit:
		raw *= 2.0
	var def: int = 0 if ignore_def else target.defense
	var dealt: int = target.take_damage(max(1, int(round(raw)) - def))
	run_best_hit = max(run_best_hit, dealt)
	var flair := ""
	if force_crit:
		flair = "  [color=#ffd24a]COUP MORTEL![/color]"
	elif is_execute:
		flair = "  [color=#c0303a]EXÉCUTION![/color]"
	elif crit:
		flair = "  [color=#ffec5a]CRITIQUE![/color]"
	add_message("%s %s (-%d)%s" % [verb, target.display_name, dealt, flair])
	if player.has_power("venin") and target.is_alive():
		apply_poison(target, 3, maxf(1.0, round(float(dealt) * 0.25)))
	if player.lifesteal_pct > 0.0 and dealt > 0:
		var healed: int = int(ceil(dealt * player.lifesteal_pct))
		if healed > 0:
			player.heal(healed)
			add_message("[color=#ff7a8a]Vol de vie : +%d PV.[/color]" % healed)
	if not target.is_alive():
		on_enemy_killed(target)
		return
	if player.has_proc("frappe_double") and rng.randf() < player.proc_value("frappe_double"):
		var raw2: int = int(round(base_raw * 0.5))
		var dealt2: int = target.take_damage(max(1, raw2 - target.defense))
		run_best_hit = max(run_best_hit, dealt2)
		add_message("[color=#ffb86a]Frappe double sur %s (-%d).[/color]" % [target.display_name, dealt2])
		if player.lifesteal_pct > 0.0 and dealt2 > 0:
			player.heal(int(ceil(dealt2 * player.lifesteal_pct)))
		if not target.is_alive():
			on_enemy_killed(target)

## Attaque d'un ENNEMI vers le joueur : gère esquive, défense, épines, résurrection.
func _enemy_attack_player(attacker: Entity) -> void:
	if rng.randf() < player.dodge_chance:
		add_message("[color=#b3a8e0]Tu esquives %s ![/color]" % attacker.display_name)
		return
	player.take_damage(max(1, attacker.atk - player.defense))
	add_message("[color=#ff8a8a]%s te frappe.[/color]" % attacker.display_name)
	if player.thorns_flat > 0:
		var d2: int = attacker.take_damage(player.thorns_flat)
		add_message("[color=#cdd66a]Épines : %s subit %d.[/color]" % [attacker.display_name, d2])
		if not attacker.is_alive():
			on_enemy_killed(attacker)
	_check_revive()

func _check_revive() -> void:
	if player.hp <= 0 and player.revive_available():
		player.revives_used += 1
		player.hp = max(1, int(player.max_hp * 0.5))
		add_message("[color=#ffd24a]✦ Une résurrection te ramène à la vie (50% PV) ![/color]")

func on_enemy_killed(e: Entity) -> void:
	if not enemies.has(e):
		return
	run_kills += 1
	run_shards += e.shard_value
	player.xp += e.shard_value
	if player.has_proc("moisson"):
		var bonus_shards: int = int(round(player.proc_value("moisson")))
		run_shards += bonus_shards
		add_message("[color=#ffd24a]Moisson : +%d Éclats.[/color]" % bonus_shards)
	if player.has_proc("soif_de_sang"):
		var heal_amt: int = int(round(player.max_hp * player.proc_value("soif_de_sang")))
		if heal_amt > 0:
			player.heal(heal_amt)
			add_message("[color=#7cfc9a]Soif de sang : +%d PV.[/color]" % heal_amt)
	var death_pos: Vector2i = e.pos()
	var was_legendary: bool = e.is_legendary
	enemies.erase(e)
	if player.has_power("detonation") and _chebyshev(death_pos, player.pos()) <= 3:
		var boom: int = maxi(2, player.atk / 2 + player.ability_power)
		var hits: int = aoe_attack(death_pos, 1, boom, "Détonation frappe")
		if hits > 0:
			add_message("[color=#ff8a4a]✹ %s explose au contact de la mort.[/color]" % e.display_name)
	if e.is_boss:
		add_message("[color=#ffd24a]★ Le Gardien tombe ! +%d Éclats. La voie est libre.[/color]" % e.shard_value)
		var reward: Dictionary = Data.generate_boss_reward(floor_num, rng)
		add_message("[color=#ffb86a]✦ Butin garanti du Gardien : %s ![/color]" % reward["name"])
		_bag_add(reward)
		_drop_skill(death_pos, true)        # le boss lâche aussi une compétence
		if floor_num % 15 == 0:
			_drop_power(death_pos)
	else:
		add_message("%s meurt. [color=#ffd24a]+%d Éclats[/color]." % [e.display_name, e.shard_value])
		if was_legendary:
			_drop_power(death_pos)
		elif rng.randf() < SKILL_DROP_CHANCE:
			_drop_skill(death_pos, false)

# --- Butin & inventaire -------------------------------------------------------
func _pickup_loot_at(p: Vector2i) -> void:
	for item in loot.duplicate():
		if item["pos"] == p:
			loot.erase(item)
			match item["kind"]:
				"artifact":
					_acquire_artifact(item["data"])
				"power":
					_acquire_power(item["data"])
				"skill":
					_acquire_skill(String(item["data"]["id"]))
				_:
					_bag_add(item["data"])

# --- Compétences (Phase 2) ----------------------------------------------------
## Tire une compétence droppable (hors bases, non encore connue), pondérée par
## rareté, et la dépose au sol à `pos`. `guaranteed` réservé aux boss.
func _drop_skill(pos: Vector2i, _guaranteed: bool) -> void:
	var id: String = _pick_droppable_skill()
	if id == "":
		return
	loot.append({ "pos": pos, "kind": "skill", "glyph": "✦", "sprite": "artifact",
		"color": Data.skill_rarity_color(id), "data": { "id": id } })
	add_message("[color=#b8a0ff]✦ Une compétence scintille au sol…[/color]")

func _pick_droppable_skill() -> String:
	var pool: Array = []
	var weights: Array = []
	var total: float = 0.0
	for id in Data.SKILLS:
		var s: Dictionary = Data.SKILLS[id]
		if String(s["rarity"]) == "base" or known_skills.has(id):
			continue
		var w: float = float(Data.SKILL_RARITIES[s["rarity"]]["weight"])
		pool.append(id); weights.append(w); total += w
	if pool.is_empty():
		return ""
	var roll: float = rng.randf() * total
	for i in pool.size():
		roll -= weights[i]
		if roll <= 0.0:
			return pool[i]
	return pool[pool.size() - 1]

func _acquire_skill(id: String) -> void:
	if not Data.SKILLS.has(id):
		return
	if known_skills.has(id) or String(Data.SKILLS[id]["rarity"]) == "base":
		run_shards += 8
		add_message("Compétence déjà connue : %s (+8 Éclats)." % Data.SKILLS[id]["name"])
		return
	known_skills.append(id)
	add_message("[color=#c8b0ff]✦ Compétence apprise : %s — %s[/color]" % [Data.SKILLS[id]["name"], Data.SKILLS[id]["desc"]])
	refresh()

## Liste des compétences sélectionnables avec l'arme équipée (base du type + apprises compatibles).
func selectable_skills() -> Array:
	var wtype: String = String(player.equipment.get("arme", {}).get("weapon_type", ""))
	if wtype == "":
		return []
	var out: Array = [Data.WEAPON_TYPE_BASE_SKILL[wtype]]
	for id in known_skills:
		if String(Data.SKILLS.get(id, {}).get("wtype", "")) == wtype and not out.has(id):
			out.append(id)
	return out

## Définit la compétence active (doit être compatible avec l'arme équipée).
func select_skill(id: String) -> void:
	if not selectable_skills().has(id):
		return
	player.active_skill_id = id
	player.recompute_stats()
	add_message("Compétence active : [color=#c8b0ff]%s[/color]." % Data.SKILLS[id]["name"])
	refresh()

func _bag_add(item: Dictionary) -> void:
	_note_item(item)
	if inventory.size() >= INV_CAP:
		var s: int = int(item.get("salvage", 3))
		run_shards += s
		add_message("Sac plein : %s recyclé (+%d Éclats)." % [item.get("name", "?"), s])
		return
	inventory.append(item)
	var rc: Color = item.get("rarity_color", Color(0.85, 0.85, 0.9))
	add_message("Ramassé : [color=#%s]%s[/color].  [I] pour gérer." % [rc.to_html(false), item.get("name", "?")])

## Mémorise l'objet d'équipement le plus rare obtenu du run (journal de fin).
func _note_item(item: Dictionary) -> void:
	if item.get("kind", "") != "equip":
		return
	if run_best_item.is_empty() or _rarity_rank(item) > _rarity_rank(run_best_item):
		run_best_item = item

func _rarity_rank(item: Dictionary) -> int:
	match item.get("rarity", ""):
		"legendaire": return 4
		"epique": return 3
		"rare": return 2
		"commun": return 1
	return 0

func equip_item(item: Dictionary) -> void:
	if item.get("kind", "") != "equip":
		return
	inventory.erase(item)
	var slot: String = item["slot"]
	if player.equipment.has(slot):
		var old: Dictionary = player.equipment[slot]
		if inventory.size() < INV_CAP:
			inventory.append(old)
		else:
			run_shards += int(old.get("salvage", 3))
	player.equipment[slot] = item
	player.recompute_stats()
	add_message("[color=#9fe0ff]Équipé : %s[/color]" % item["name"])
	refresh()

func unequip_item(slot: String) -> void:
	if not player.equipment.has(slot):
		return
	var it: Dictionary = player.equipment[slot]
	player.equipment.erase(slot)
	if inventory.size() < INV_CAP:
		inventory.append(it)
	else:
		run_shards += int(it.get("salvage", 3))
	player.recompute_stats()
	add_message("Déséquipé : %s" % it["name"])
	refresh()

func salvage_item(item: Dictionary) -> void:
	inventory.erase(item)
	var s: int = int(item.get("salvage", 3))
	run_shards += s
	add_message("Recyclé : %s (+%d Éclats)." % [item.get("name", "?"), s])
	refresh()

func use_consumable(item: Dictionary) -> void:
	match item.get("effect", ""):
		"heal_pct":
			var amt: int = int(ceil(player.max_hp * float(item["value"])))
			player.heal(amt)
			add_message("[color=#7aff8a]%s : +%d PV.[/color]" % [item["name"], amt])
		"heal_full":
			player.heal(player.max_hp)
			add_message("[color=#7aff8a]%s : PV au maximum ![/color]" % item["name"])
		"shards":
			var s: int = int(item["value"])
			run_shards += s
			add_message("[color=#ffd24a]%s : +%d Éclats.[/color]" % [item["name"], s])
	inventory.erase(item)
	refresh()

func _acquire_artifact(def: Dictionary) -> void:
	if player.has_artifact(def["id"]):
		run_shards += 5
		add_message("Artefact %s déjà actif (+5 Éclats)." % def["name"])
		return
	player.artifacts.append(def)
	player.recompute_stats()
	add_message("[color=#f0b8ff]✦ Artefact : %s — %s[/color]" % [def["name"], def["desc"]])
	refresh()

# --- Pouvoirs passifs (Phase 3) ------------------------------------------------
func _drop_power(pos: Vector2i) -> void:
	var def: Dictionary = _pick_power_def()
	if def.is_empty():
		return
	loot.append({ "pos": pos, "kind": "power", "glyph": Data.POWER_GLYPH,
		"sprite": "artifact", "color": def["color"], "data": def })
	add_message("[color=#ffb84a]Ω Un pouvoir puissant scintille au sol…[/color]")

func _pick_power_def() -> Dictionary:
	var pool: Array = []
	for def in Data.POWERS:
		if not player.has_power(def["id"]):
			pool.append(def)
	if pool.is_empty():
		return {}
	return pool[rng.randi_range(0, pool.size() - 1)]

## Renvoie le pouvoir déjà actif qui s'exclut mutuellement avec `def` (vide si aucun).
func _power_conflict(def: Dictionary) -> Dictionary:
	for ex_id in def.get("excludes", []):
		for p in player.powers:
			if p.get("id", "") == ex_id:
				return p
	for p in player.powers:
		if p.get("excludes", []).has(def["id"]):
			return p
	return {}

func _acquire_power(def: Dictionary) -> void:
	if player.has_power(def["id"]):
		run_shards += 10
		add_message("Pouvoir %s déjà actif (+10 Éclats)." % def["name"])
		return
	var conflict: Dictionary = _power_conflict(def)
	if not conflict.is_empty():
		run_shards += 10
		add_message("[color=#ff8a8a]%s est incompatible avec %s, déjà actif (+10 Éclats).[/color]" % [def["name"], conflict["name"]])
		return
	player.powers.append(def)
	player.recompute_stats()
	add_message("[color=#ffb84a]Ω Pouvoir : %s — %s[/color]" % [def["name"], def["desc"]])
	refresh()

## Déclenche les pouvoirs à activation automatique (drone/tourelle), après l'action du joueur.
func _trigger_powers() -> void:
	if not player.is_alive():
		return
	if player.has_power("drone"):
		var t: Entity = _nearest_enemy_in_range(6)
		if t != null:
			_player_attack(t, maxi(1, int(round(player.atk * 0.5)) + player.ability_power), "Le drone tire sur")
	if player.has_power("turret"):
		var t2: Entity = _nearest_enemy_in_range(8)
		if t2 != null:
			aoe_attack(t2.pos(), 1, maxi(1, int(round(player.atk * 0.35)) + player.ability_power), "La tourelle frappe")

# --- Boucle de tour à énergie -------------------------------------------------
func _player_acted() -> void:
	player.energy -= Entity.ACTION_COST
	_begin_turn(player)
	player.tick_cooldown()
	if not player.is_alive():
		game_over()
		return
	_trigger_powers()
	if not player.is_alive():
		game_over()
		return
	advance_world()
	if state != State.PLAYING:
		return
	refresh()
	_check_level_up()

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
			player.energy += player.effective_speed()
			for e in enemies:
				if e.is_alive():
					e.energy += e.effective_speed()
			continue
		for e in ready:
			if not e.is_alive():
				continue
			e.energy -= Entity.ACTION_COST
			var stunned: bool = _begin_turn(e)
			if not e.is_alive():        # un DoT (poison/brûlure) l'a achevé
				on_enemy_killed(e)
				continue
			if stunned:
				add_message("[color=#b3a8e0]%s est paralysé.[/color]" % e.display_name)
				continue
			_enemy_act(e)
			if not player.is_alive():
				game_over()
				return

## Début de tour d'une entité : régénération + tic des statuts (DoT, durées).
## Renvoie true si l'entité est PARALYSÉE ce tour (elle saute son action).
func _begin_turn(e: Entity) -> bool:
	if not e.is_alive():
		return false
	var stunned: bool = e.has_status("stun")
	if e.hp_regen > 0:
		e.heal(e.hp_regen)
	var dot: int = e.tick_statuses()
	if dot > 0:
		if e.faction == Entity.Faction.PLAYER:
			add_message("[color=#9fdf6a]Tu subis %d dégâts (poison/brûlure).[/color]" % dot)
		else:
			add_message("[color=#9fdf6a]%s subit %d (poison/brûlure).[/color]" % [e.display_name, dot])
	return stunned

func _enemy_act(e: Entity) -> void:
	if e.is_boss and not e.enraged and e.hp <= e.max_hp * 0.5:
		e.enraged = true
		e.atk = int(round(e.atk * 1.4))
		add_message("[color=#ff4040]⚡ Le Gardien entre en RAGE ! Ses coups redoublent.[/color]")
	if _manhattan(e.pos(), player.pos()) == 1:
		_enemy_attack_player(e)
		return
	var dx: int = signi(player.x - e.x)
	var dy: int = signi(player.y - e.y)
	var tries: Array
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

# --- Boutique -----------------------------------------------------------------
func open_shop() -> void:
	state = State.CHOICE
	shop_stock = []
	for i in 3:
		var slot: String = Data.SLOTS[rng.randi_range(0, Data.SLOTS.size() - 1)]
		var it: Dictionary = Data.generate_item(slot, floor_num + 1, rng)
		it["price"] = int(it["salvage"] * 2.5)
		shop_stock.append(it)
	for i in 2:
		var c: Dictionary = Data.generate_consumable(floor_num, rng)
		c["price"] = 8 + floor_num
		shop_stock.append(c)
	if rng.randf() < 0.5:
		var pdef: Dictionary = _pick_power_def()
		if not pdef.is_empty():
			var pitem: Dictionary = pdef.duplicate(true)
			pitem["kind"] = "power"
			pitem["price"] = 40
			shop_stock.append(pitem)
	hud.hide_map()
	hud.show_shop(shop_stock, run_shards)

func buy_shop_item(item: Dictionary) -> void:
	var price: int = int(item.get("price", 99999))
	if run_shards < price or not shop_stock.has(item):
		return
	run_shards -= price
	shop_stock.erase(item)
	if item.get("kind", "") == "power":
		_acquire_power(item)
	else:
		_bag_add(item)
	hud.show_shop(shop_stock, run_shards)

func buy_shop_heal() -> void:
	var price := 15
	if run_shards < price:
		return
	run_shards -= price
	player.heal(int(player.max_hp * 0.5))
	add_message("Soin à la boutique (+50% PV).")
	hud.show_shop(shop_stock, run_shards)

func leave_shop() -> void:
	_back_to_map()

# --- Événement ----------------------------------------------------------------
func open_event() -> void:
	state = State.CHOICE
	current_event = Data.EVENTS[rng.randi_range(0, Data.EVENTS.size() - 1)]
	hud.hide_map()
	hud.show_event(current_event)

func resolve_event(choice_idx: int) -> void:
	_apply_event_effect(current_event["choices"][choice_idx])
	if not player.is_alive():
		game_over()
		return
	_back_to_map()

func _apply_event_effect(ch: Dictionary) -> void:
	match ch.get("type", "none"):
		"heal":
			var a: int = int(player.max_hp * float(ch["value"]))
			player.heal(a)
			add_message("Tu récupères %d PV." % a)
		"item_consumable":
			_bag_add(Data.generate_consumable(floor_num, rng))
		"shards":
			run_shards += int(ch["value"])
			add_message("+%d Éclats." % int(ch["value"]))
		"gamble":
			if rng.randf() < 0.6:
				run_shards += 30
				add_message("[color=#9fff9f]Chance ! +30 Éclats.[/color]")
			else:
				player.take_damage(10)
				add_message("[color=#ff8a8a]Piège ! −10 PV.[/color]")
		"trade_artifact":
			if run_shards >= 20:
				var a: Dictionary = _pick_artifact_def()
				if not a.is_empty():
					run_shards -= 20
					_acquire_artifact(a)
				else:
					add_message("Le marchand n'a plus rien pour toi.")
			else:
				add_message("Pas assez d'Éclats.")
		"stat_atk":
			player.base_atk += 3
			player.recompute_stats()
			add_message("Entraînement : +3 ATK (ce run).")
		"stat_hp":
			player.base_max_hp += 15
			player.recompute_stats()
			player.heal(15)
			add_message("Trempe : +15 PV max (ce run).")
		"stat_regen":
			player.base_hp_regen += 1
			player.recompute_stats()
			add_message("Méditation : +1 Régén PV/tour (ce run).")
		"cursed_altar":
			player.base_atk += 5
			player.base_max_hp = max(10, player.base_max_hp - 10)
			player.recompute_stats()
			add_message("[color=#ff8a8a]Autel maudit : +5 ATK mais −10 PV max (ce run).[/color]")
		"buy_revive":
			if run_shards >= 15:
				run_shards -= 15
				player.talents.append({ "name": "Bénédiction", "mods": { "max_revives": 1 } })
				player.recompute_stats()
				add_message("[color=#ffd24a]Bénédiction : +1 résurrection.[/color]")
			else:
				add_message("Pas assez d'Éclats.")
		_:
			add_message("Tu passes ton chemin.")

# --- Repos (feu de camp) ------------------------------------------------------
func open_rest() -> void:
	state = State.CHOICE
	hud.hide_map()
	hud.show_rest()

func rest_choice(kind: String) -> void:
	if kind == "heal":
		var amt: int = int(player.max_hp * 0.4)
		player.heal(amt)
		add_message("Repos : +%d PV." % amt)
	else:
		player.base_atk += 3
		player.recompute_stats()
		add_message("Entraînement : +3 ATK (ce run).")
	_back_to_map()

func game_over() -> void:
	var stats := {
		"floor": floor_num, "level": player.level, "kills": run_kills,
		"best_hit": run_best_hit, "shards": run_shards,
		"item": str(run_best_item.get("name", "")),
		"item_color": run_best_item.get("rarity_color", Color(0.82, 0.82, 0.88)).to_html(false),
	}
	GameState.add_shards(run_shards)
	GameState.record_run(stats)
	state = State.GAMEOVER
	hud.show_gameover("Tu es tombé à l'Étage %d (niveau %d)." % [floor_num, player.level])

# --- Montée de niveau & talents -----------------------------------------------
func xp_to_next(level: int) -> int:
	return 6 + level * 5

func _check_level_up() -> void:
	while player.xp >= xp_to_next(player.level):
		player.xp -= xp_to_next(player.level)
		player.level += 1
		pending_levelups += 1
		add_message("[color=#9fff9f]★ Niveau %d ![/color]" % player.level)
	if pending_levelups > 0 and state == State.PLAYING:
		_open_levelup()

func _open_levelup() -> void:
	state = State.LEVELUP
	hud.show_levelup(player.level)

func pick_talent(t: Dictionary) -> void:
	player.talents.append(t)
	player.recompute_stats()
	add_message("Talent acquis : [color=#9fff9f]%s[/color]." % t["name"])
	pending_levelups -= 1
	if pending_levelups > 0:
		_open_levelup()
	else:
		state = State.PLAYING
		hud.hide_overlay()
		refresh()

# --- Inventaire (état ; l'affichage est dans Hud) -----------------------------
func open_inventory() -> void:
	state = State.INVENTORY
	hud.show_inventory()

func close_inventory() -> void:
	state = State.PLAYING
	hud.hide_overlay()
	refresh()

# --- Divers -------------------------------------------------------------------
func refresh() -> void:
	if dungeon != null and player != null:
		dungeon.reveal(player.pos(), player.vision)
		_update_camera()
	map_view.refresh(dungeon, [player] + enemies, loot)
	hud.refresh()

func add_message(msg: String) -> void:
	messages.append(msg)
	while messages.size() > MAX_LOG:
		messages.pop_front()

func enemy_at(x: int, y: int) -> Entity:
	for e in enemies:
		if e.is_alive() and e.x == x and e.y == y:
			return e
	return null

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return max(abs(a.x - b.x), abs(a.y - b.y))
