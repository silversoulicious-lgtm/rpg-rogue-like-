## Coordinateur du jeu : état, génération d'étage, combat tour-par-tour, IA,
## capacités, butin/inventaire, montée de niveau. Tout l'AFFICHAGE est délégué
## à Hud (scripts/Hud.gd). "Les Strates" — roguelike d'ascension de tour.
extends Node2D

enum State { HUB, MAP, PLAYING, CHOICE, LEVELUP, INVENTORY, DEAD }

const MAP_W := 32
const MAP_H := 19
const MAX_LOG := 8
const INV_CAP := 16

var state: int = State.HUB
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
	return_to_hub("")

# --- Flux d'écrans ------------------------------------------------------------
func return_to_hub(summary: String) -> void:
	state = State.HUB
	hud.show_hub(summary)

func choose_hero(hero_id: String) -> void:
	GameState.last_hero = hero_id
	GameState.save_game()
	start_run(hero_id)

func start_run(hero_id: String) -> void:
	var h: Dictionary = Data.HEROES[hero_id]
	player = Entity.new()
	player.display_name = h["name"]
	player.glyph = h["glyph"]
	player.sprite = hero_id
	player.color = h["color"]
	player.faction = Entity.Faction.PLAYER
	player.base_max_hp = int(h["max_hp"]) + GameState.bonus_hp()
	player.base_atk = int(h["atk"]) + GameState.bonus_atk()
	player.base_magic = int(h["magic"])
	player.base_defense = int(h["defense"])
	player.base_speed = int(h["speed"])
	player.base_hp_regen = int(h["hp_regen"])
	player.base_ability_power = GameState.bonus_ability_power()
	player.base_ability_cd = int(h["ability_cd"])
	player.ability_id = h["ability_id"]
	player.ability_range = int(h["ability_range"])
	player.ability_cd = 0
	player.equipment = {}
	player.artifacts = []
	player.talents = []
	player.level = 1
	player.xp = 0
	player.revives_used = 0
	player.recompute_stats()
	player.hp = player.max_hp

	floor_num = 1
	run_shards = 0
	pending_levelups = 0
	messages.clear()
	loot.clear()
	inventory.clear()
	add_message("[color=#9b8cff]Tu entres dans la Tour. Trace ta voie vers le Gardien.[/color]")
	map_act = 0
	_start_act()

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
	dungeon = Dungeon.new(MAP_W, MAP_H, rng)
	player.x = dungeon.start.x
	player.y = dungeon.start.y
	player.energy = Entity.ACTION_COST   # le joueur agit en premier

	enemies.clear()
	loot.clear()
	var occupied: Array = [dungeon.start, dungeon.stairs]
	var is_elite: bool = node_type == "elite"
	var is_boss: bool = node_type == "boss"

	var count: int = min(3 + floor_num, 12)
	if is_elite:
		count = min(count + 2, 14)
	for p in dungeon.random_floor_tiles(count, rng, occupied):
		var e: Entity = _make_enemy(_pick_enemy_def(), floor_num, p)
		if is_elite:
			e.max_hp = int(e.max_hp * 1.25)
			e.hp = e.max_hp
			e.atk = int(e.atk * 1.2)
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

	var loot_count: int = rng.randi_range(1, 3) + (1 if is_elite else 0)
	for p in dungeon.random_floor_tiles(loot_count, rng, occupied):
		occupied.append(p)
		_spawn_loot(p, is_elite)

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

func _center_map() -> void:
	var gsize: Vector2 = map_view.grid_pixel_size()
	var pa: Vector2 = hud.play_area()
	map_view.position = Vector2(
		round((pa.x - gsize.x) * 0.5),
		round((pa.y - gsize.y) * 0.5) + 8
	)

# --- Entrées clavier ----------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = event.keycode
	if state == State.INVENTORY:
		if k == KEY_I or k == KEY_ESCAPE:
			close_inventory()
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
			hit = _do_ranged(player.magic * 2 + player.atk + player.ability_power, "[color=#7ab8ff]Éclair[/color] foudroie")
		"volley":
			hit = _do_ranged(int(player.atk * 1.5) + player.magic + player.ability_power, "[color=#7aff8a]Flèche[/color] transperce")
	if not hit:
		add_message("[color=#888888]Aucune cible à portée.[/color]")
		refresh()
		return
	player.ability_cd = player.ability_cd_max
	_player_acted()

func _do_whirl() -> bool:
	var base: int = player.atk + player.magic + player.ability_power
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
## Attaque du JOUEUR vers un ennemi : gère critique, défense, vol de vie,
## et les procs d'objets uniques (exécution, frénésie, premier coup, frappe double).
func _player_attack(target: Entity, base_raw: int, verb: String) -> void:
	var raw: float = float(base_raw)
	if player.has_proc("frenesie") and player.hp <= player.max_hp * 0.4:
		raw *= 1.0 + player.proc_value("frenesie")
	if player.has_proc("execution") and target.hp <= target.max_hp * 0.25:
		raw *= 1.0 + player.proc_value("execution")
	var force_crit: bool = player.has_proc("premier_coup") and not first_strike_used
	first_strike_used = true
	var crit: bool = force_crit or rng.randf() < player.crit_chance
	if crit:
		raw *= 2.0
	var dealt: int = target.take_damage(max(1, int(round(raw)) - target.defense))
	add_message("%s %s (-%d)%s" % [verb, target.display_name, dealt,
		"  [color=#ffec5a]CRITIQUE![/color]" if crit else ""])
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
	enemies.erase(e)
	if e.is_boss:
		add_message("[color=#ffd24a]★ Le Gardien tombe ! +%d Éclats. La voie est libre.[/color]" % e.shard_value)
	else:
		add_message("%s meurt. [color=#ffd24a]+%d Éclats[/color]." % [e.display_name, e.shard_value])

# --- Butin & inventaire -------------------------------------------------------
func _pickup_loot_at(p: Vector2i) -> void:
	for item in loot.duplicate():
		if item["pos"] == p:
			loot.erase(item)
			if item["kind"] == "artifact":
				_acquire_artifact(item["data"])
			else:
				_bag_add(item["data"])

func _bag_add(item: Dictionary) -> void:
	if inventory.size() >= INV_CAP:
		var s: int = int(item.get("salvage", 3))
		run_shards += s
		add_message("Sac plein : %s recyclé (+%d Éclats)." % [item.get("name", "?"), s])
		return
	inventory.append(item)
	var rc: Color = item.get("rarity_color", Color(0.85, 0.85, 0.9))
	add_message("Ramassé : [color=#%s]%s[/color].  [I] pour gérer." % [rc.to_html(false), item.get("name", "?")])

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

# --- Boucle de tour à énergie -------------------------------------------------
func _player_acted() -> void:
	player.energy -= Entity.ACTION_COST
	_apply_regen(player)
	player.tick_cooldown()
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
	hud.hide_map()
	hud.show_shop(shop_stock, run_shards)

func buy_shop_item(item: Dictionary) -> void:
	var price: int = int(item.get("price", 99999))
	if run_shards < price or not shop_stock.has(item):
		return
	run_shards -= price
	shop_stock.erase(item)
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
	GameState.add_shards(run_shards)
	GameState.record_floor(floor_num)
	return_to_hub("💀 Tu es tombé à l'Étage %d (niveau %d). Butin du run : %d Éclats (ajoutés à la banque)." % [floor_num, player.level, run_shards])

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
