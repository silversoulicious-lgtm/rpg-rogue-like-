## Coordinateur du jeu : état, génération d'étage, combat tour-par-tour, IA,
## capacités, butin/inventaire, montée de niveau. Tout l'AFFICHAGE est délégué
## à Hud (scripts/Hud.gd). "Les Strates" — roguelike d'ascension de tour.
extends Node2D

enum State { TITLE, LOADOUT, META, HUB, PLAYING, PAUSED, CHOICE, LEVELUP, INVENTORY, GAMEOVER }

const MAX_LOG := 200
const INV_CAP := 16
const NO_TILE := Vector2i(-9999, -9999)   # sentinelle "aucune case trouvée"
const ABANDON_SHARD_MULT := 0.75          # pénalité d'Éclats en cas d'abandon volontaire
const REPEAT_INITIAL_DELAY := 0.25        # délai avant répétition d'une touche de mouvement maintenue
const REPEAT_RATE := 0.09                 # cadence de répétition une fois lancée
var _repeat_at: float = 0.0               # horloge (Time.get_ticks_msec) du prochain pas répété

var state: int = State.TITLE
var rng := RandomNumberGenerator.new()
var run_seed: int = 0   # seed du run en cours (start_run) — affichée pause/journal, copiable

# Run en cours
var player: Entity = null
var enemies: Array = []          # Array[Entity]
var loot: Array = []             # Array[dict] : { pos, kind, glyph, sprite, color, data }
var hazards: Array = []          # pièges au sol : Array[{ pos, glyph, color, status:{id,turns,value}, dmg }]
var dungeon: Dungeon = null
var floor_num: int = 1
var run_shards: int = 0
var messages: Array = []
var inventory: Array = []        # sac : Array[item dict]
var pending_levelups: int = 0

# Progression des étages (linéaire, sans carte à embranchements) : le type du
# prochain nœud est tiré au sort (cf. _roll_node_type/_advance), un Gardien est
# garanti tous les ACT_LENGTH étages réels (Combat/Élite).
const ACT_LENGTH := 5
var map_act: int = 0       # nombre de Gardiens vaincus ce run (sélection du boss)
var act_floor: int = 0     # étages réels complétés depuis le dernier Gardien
var _act_rest_done: bool = false   # garantit 1 pause Repos/Boutique avant chaque Gardien
var current_node_type: String = "combat"
# Nature de l'écran CHOICE actuellement ouvert : "reward"/"shop"/"event"/"rest".
# Plusieurs types de nœud partagent State.CHOICE ; ce tag les désambiguïse pour
# le harnais d'auto-jeu (Phase 5.1) et toute logique qui inspecte l'état.
var current_choice: String = ""
var shop_stock: Array = []
var current_event: Dictionary = {}
var first_strike_used: bool = false   # pour le proc d'objet unique "premier_coup"

# Compétences (Phase 2)
var known_skills: Array = []          # ids de compétences droppées et apprises (hors bases)
var last_dir: Vector2i = Vector2i(1, 0)   # dernière direction de déplacement (visée auto)
var _attack_dmg_type: String = "phys"  # contexte de type de dégâts (phys/magic) pour les résistances
var _attack_elem: String = ""          # élément de la compétence en cours (fire/frost/lightning) — réactions de terrain
var _conducted_cells: Dictionary = {}  # cases d'eau déjà conduites pendant CE lancer (une décharge max par plan d'eau)
const SKILL_DROP_CHANCE := 0.06       # chance qu'un monstre lâche une compétence
const LEGENDARY_CHANCE := 0.025       # chance qu'un monstre soit légendaire (lâche un pouvoir)
const POI_CHANCE := 0.14              # chance qu'une structure de POI (coffre rare) apparaisse sur l'étage

# Statistiques du run en cours (pour le journal de fin de run)
var run_kills: int = 0
var run_best_hit: int = 0
var run_best_item: Dictionary = {}
var run_bosses: int = 0          # Gardiens vaincus ce run (gain de Connaissances)
var pending_rewards: Array = []  # récompenses de fin d'étage proposées (Phase 4)
var last_damage_source: String = ""   # source du dernier coup encaissé (récap de mort)
var _forest_fire_warned: bool = false  # message/son d'alerte incendie une seule fois par étage
const RUN_TIMELINE_CAP := 40
var run_timeline: Array = []     # [String] : grands jalons du run (entrée biome, boss, pouvoir...)
var _last_timeline_biome: String = ""  # évite de spammer une entrée à chaque étage du même biome

# Serments actifs pour le run en cours (ids de Data.OATHS, choisis au loadout)
var active_oaths: Array = []

# Hub (Pied de la Tour) : petite ville explorable hors run, accès aux écrans
# de méta-progression via des bâtiments plutôt qu'une liste de boutons.
var town: Town = null
var hub_pos: Vector2i = Vector2i.ZERO
var town_view: Node2D
# État vers lequel les boutons "Retour" des écrans de méta doivent ramener :
# TITLE (accès direct depuis l'écran-titre) ou HUB (accès depuis une visite
# de bâtiment). Réglé juste avant d'ouvrir l'écran concerné.
var _menu_return_state: int = State.TITLE

var map_view: Node2D
var hud                          # instance de Hud (scripts/Hud.gd)

func _ready() -> void:
	rng.randomize()
	_setup_input_actions()
	map_view = Node2D.new()
	map_view.set_script(load("res://scripts/MapView.gd"))
	add_child(map_view)
	town_view = Node2D.new()
	town_view.set_script(load("res://scripts/TownView.gd"))
	town_view.visible = false
	add_child(town_view)
	map_view.visible = false
	hud = Node.new()
	hud.set_script(load("res://scripts/Hud.gd"))
	add_child(hud)
	hud.setup(self)
	map_view.hud = hud
	map_view.view_size = hud.play_area()
	get_viewport().size_changed.connect(_on_viewport_resized)
	return_to_title()

## La fenêtre a changé de taille/ratio : recale la zone de jeu et force la
## vignette (mise en cache à la 1re taille) à se régénérer.
func _on_viewport_resized() -> void:
	if map_view == null or hud == null:
		return
	map_view.view_size = hud.play_area()
	map_view._vignette_tex = null
	refresh()

## Actions liées par touche PHYSIQUE (position sur le clavier, pas le
## caractère produit) : WASD/flèches/HJKL fonctionnent quelle que soit la
## disposition (AZERTY, QWERTY...).
func _setup_input_actions() -> void:
	_bind_action("move_up", [KEY_W, KEY_UP, KEY_K])
	_bind_action("move_down", [KEY_S, KEY_DOWN, KEY_J])
	_bind_action("move_left", [KEY_A, KEY_LEFT, KEY_H])
	_bind_action("move_right", [KEY_D, KEY_RIGHT, KEY_L])
	_bind_action("wait", [KEY_PERIOD, KEY_KP_5])
	_bind_action("ability", [KEY_SPACE, KEY_E])
	_bind_action("inventory", [KEY_I])
	_bind_action("cancel", [KEY_ESCAPE])

func _bind_action(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)

# --- Flux d'écrans ------------------------------------------------------------
## Écran-titre (point d'entrée du jeu).
func return_to_title() -> void:
	_menu_return_state = State.TITLE
	state = State.TITLE
	hud.show_title()

## Ramène vers l'écran-titre ou le Hub selon d'où l'écran courant a été ouvert
## (réglé par _hub_enter_building juste avant d'ouvrir un bâtiment). À utiliser
## par les boutons "Retour" des écrans de méta plutôt que return_to_title
## directement, pour ne pas éjecter vers le titre une visite venue du Hub.
func return_to_previous() -> void:
	if _menu_return_state == State.HUB:
		enter_hub()
	else:
		return_to_title()

## Écran de loadout : choix de l'arme de départ (fiches détaillées).
func open_loadout() -> void:
	state = State.LOADOUT
	hud.show_loadout()

## Sanctuaire : méta-progression entre les runs.
func open_meta() -> void:
	state = State.META
	hud.show_meta()

## Arbre de Connaissances : déblocage de systèmes via la 2ᵉ monnaie méta.
func open_knowledge() -> void:
	state = State.META
	hud.show_knowledge()

## Codex consultable (catalogue des découvertes).
func open_codex() -> void:
	state = State.META
	hud.show_codex()

# --- Hub (Pied de la Tour) -----------------------------------------------------
## Entre dans le Hub : la ville est créée une seule fois (disposition fixe) et
## Aria conserve sa position d'une visite à l'autre (elle ne revient pas
## systématiquement au centre en sortant d'un bâtiment).
func enter_hub() -> void:
	if town == null:
		town = Town.new()
		hub_pos = town.player_start
	map_view.visible = false
	town_view.visible = true
	state = State.HUB
	hud.show_hub()
	town_view.refresh(town, hub_pos)

## Déplacement libre dans le Hub (pas de tour par tour). Marcher sur la case
## d'un bâtiment déclenche automatiquement son écran, comme l'escalier en donjon.
func _hub_try_move(dx: int, dy: int) -> void:
	if state != State.HUB:
		return
	var nx: int = hub_pos.x + dx
	var ny: int = hub_pos.y + dy
	if not town.is_walkable(nx, ny):
		return
	hub_pos = Vector2i(nx, ny)
	town_view.refresh(town, hub_pos)
	var b: Dictionary = town.building_at(nx, ny)
	if not b.is_empty():
		_hub_enter_building(String(b["id"]))

## Bâtiments existants re-câblés vers leurs écrans actuels ; Forge/Boutique
## sont de nouveaux systèmes (progression permanente / cosmétique) pas encore
## conçus — repli en écran "bientôt disponible" plutôt qu'un bouton mort.
func _hub_enter_building(id: String) -> void:
	_menu_return_state = State.HUB
	match id:
		"tower_gate", "armurerie":
			open_loadout()
		"bibliotheque":
			open_knowledge()
		"sanctuaire":
			open_meta()
		"forge":
			state = State.CHOICE
			hud.show_hub_stub("⚒ FORGE", "Le forgeron n'a pas encore ouvert son atelier.\nBientôt : renforcement permanent de l'équipement, contre Éclats banqués.")
		"boutique":
			state = State.CHOICE
			hud.show_hub_stub("🏪 BOUTIQUE", "La boutique n'a pas encore ouvert ses portes.\nBientôt : objets cosmétiques et de confort, contre Éclats banqués.")

## Enregistre une découverte ; +1 Connaissance si c'est une première (Codex débloqué).
func _discover(category: String, key: String, label: String) -> void:
	if GameState.note_discovery(category, key):
		add_message("[color=#9fd4ff]✶ Découverte inédite : %s (+1 Connaissance).[/color]" % label)

func quit_game() -> void:
	get_tree().quit()

## Lance un run avec l'arme de départ choisie (loadout : "melee"/"ranged"/"magic").
func choose_loadout(loadout_id: String) -> void:
	GameState.last_loadout = loadout_id
	GameState.save_game()
	start_run(loadout_id)

## `forced_seed` : -1 tire une seed fraîche (rng.randomize) ; sinon la run est
## entièrement déterministe pour cette seed (même dungeon, mêmes ennemis...).
func start_run(loadout_id: String = "melee", forced_seed: int = -1) -> void:
	if forced_seed == -1:
		rng.randomize()
		run_seed = rng.seed
	else:
		rng.seed = forced_seed
		run_seed = forced_seed
	if not Data.WEAPON_TYPES.has(loadout_id):
		loadout_id = "melee"
	town_view.visible = false
	map_view.visible = true
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

	# Serments : ne garder que ceux réellement débloqués (sécurité).
	active_oaths = active_oaths.filter(func(id): return _oath_available(id))
	floor_num = 0
	run_shards = 0 if has_oath("pauvrete") else GameState.bonus_start_shards()
	run_kills = 0
	run_best_hit = 0
	run_best_item = {}
	run_bosses = 0
	pending_levelups = 0
	last_damage_source = ""
	run_timeline.clear()
	_last_timeline_biome = ""
	messages.clear()
	loot.clear()
	inventory.clear()
	_grant_starting_bonuses()
	add_message("[color=#9b8cff]Tu entres dans la Tour. Quelque part au-dessus, un Gardien t'attend.[/color]")
	map_act = 0
	act_floor = 0
	_act_rest_done = false
	_advance("combat")

## Applique les bonus de départ : méta-progression (Héritage/Instinct), déblocages
## de l'Arbre (Pacte de Pouvoir) et Serments (Pauvreté annule, Fragilité réduit les PV).
func _grant_starting_bonuses() -> void:
	if not has_oath("pauvrete"):
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
		if GameState.starts_with_power():
			var pw: Dictionary = _pick_power_def()
			if not pw.is_empty():
				player.powers.append(pw)
				add_message("[color=#ffb84a]Ω Pacte de Pouvoir : %s[/color]" % pw["name"])
	elif GameState.oaths_unlocked():
		add_message("[color=#d88a8a]Serment de Pauvreté : aucun bonus de départ.[/color]")
	if has_oath("fragilite"):
		player.base_max_hp = maxi(10, int(round(player.base_max_hp * 0.75)))
		add_message("[color=#d88a8a]Serment de Fragilité : −25% PV max.[/color]")
	player.recompute_stats()
	player.hp = player.max_hp

# --- Serments (helpers) -------------------------------------------------------
func has_oath(id: String) -> bool:
	return active_oaths.has(id)

## Un serment est disponible si la Voie est débloquée (et le palier majeur pour les majeurs).
func _oath_available(id: String) -> bool:
	var o: Dictionary = Data.oath_by_id(id)
	if o.is_empty() or not GameState.oaths_unlocked():
		return false
	return GameState.major_oaths_unlocked() if o.get("major", false) else true

## Bascule un serment (depuis l'écran de loadout). Refuse les serments non disponibles.
func toggle_oath(id: String) -> void:
	if active_oaths.has(id):
		active_oaths.erase(id)
	elif _oath_available(id):
		active_oaths.append(id)
	hud.show_loadout()

## Multiplicateur d'Éclats cumulé des serments actifs.
func oath_shard_mult() -> float:
	var m: float = 1.0
	for id in active_oaths:
		m += float(Data.oath_by_id(id).get("reward", 0.0))
	return m

## Connaissances bonus cumulées des serments actifs.
func oath_knowledge_bonus() -> int:
	var k: int = 0
	for id in active_oaths:
		k += int(Data.oath_by_id(id).get("knowledge", 0))
	return k

func _pick_any_artifact() -> Dictionary:
	var pool: Array = []
	for def in Data.ARTIFACTS:
		if not player.has_artifact(def["id"]):
			pool.append(def)
	if pool.is_empty():
		return {}
	return pool[rng.randi_range(0, pool.size() - 1)]

# --- Progression des étages (RNG, sans carte à embranchements) ---------------
## Tire le type du prochain nœud. Un Gardien est garanti tous les ACT_LENGTH
## étages réels ; une pause Repos/Boutique est elle aussi garantie juste avant
## (comme l'ancienne rangée pré-boss de RunMap), pour ne jamais foncer sur un
## Gardien à sec. L'Élite devient plus fréquente à mesure que map_act
## augmente. Boutique/Événement restent volontairement rares : ce sont des
## pauses, pas le cœur du jeu.
func _roll_node_type() -> String:
	if act_floor >= ACT_LENGTH:
		return "boss"
	if act_floor == ACT_LENGTH - 1 and not _act_rest_done:
		_act_rest_done = true
		return "rest" if rng.randf() < 0.5 else "shop"
	var elite_bonus: float = minf(0.12, map_act * 0.015)
	var combat_top: float = maxf(0.46, 0.58 - elite_bonus)
	var elite_top: float = combat_top + 0.15 + elite_bonus
	var shop_top: float = elite_top + 0.08
	var event_top: float = shop_top + 0.08
	var roll: float = rng.randf()
	if roll < combat_top:
		return "combat"
	elif roll < elite_top:
		return "elite"
	elif roll < shop_top:
		return "shop"
	elif roll < event_top:
		return "event"
	return "rest"

## Avance vers le prochain nœud : plus de choix de chemin, la suite s'enchaîne
## automatiquement (forced_type sert au tout premier étage et à celui suivant
## un Gardien, toujours un Combat pour souffler après un affrontement dur).
func _advance(forced_type: String = "") -> void:
	hud.hide_overlay()
	refresh()
	var t: String = forced_type if forced_type != "" else _roll_node_type()
	match t:
		"shop":
			open_shop()
		"event":
			open_event()
		"rest":
			open_rest()
		_:
			current_node_type = t
			floor_num += 1
			act_floor += 1
			state = State.PLAYING
			hud.show_game()
			generate_floor(current_node_type)

func _node_cleared() -> void:
	Sfx.play("stairs")
	if current_node_type == "boss":
		var healed: int = 0 if has_oath("funeste") else int(round(player.max_hp * 0.2))
		player.heal(healed)
		map_act += 1
		act_floor = 0
		_act_rest_done = false
		add_message("[color=#9b8cff]★ Gardien vaincu ! Tu poursuis l'ascension.[/color]")
		_advance("combat")
		return
	# Combat / élite : récompense de fin d'étage au choix (Phase 4).
	add_message("[color=#9b8cff]Voie dégagée. Choisis ta récompense.[/color]")
	_open_floor_reward(current_node_type == "elite")

# --- Récompense de fin d'étage (Phase 4) --------------------------------------
func _open_floor_reward(is_elite: bool) -> void:
	pending_rewards = _make_floor_rewards(is_elite)
	state = State.CHOICE
	current_choice = "reward"
	hud.show_floor_reward(pending_rewards, is_elite)

## Construit le butin de fin d'étage : soin, équipement, Éclats (+ bonus élite),
## mis à l'échelle de l'étage. Le Serment Funeste retire l'option de soin.
func _make_floor_rewards(is_elite: bool) -> Array:
	var rewards: Array = []
	var lvl: int = floor_num + (4 if is_elite else 0)
	if not has_oath("funeste"):
		var pct: float = 0.45 if is_elite else 0.30
		rewards.append({ "type": "heal", "value": pct, "color": Color(0.4, 0.9, 0.45),
			"label": "❤ Soin — +%d%% PV" % int(pct * 100),
			"desc": "Récupère une partie de tes points de vie." })
	var slot: String = Data.SLOTS[rng.randi_range(0, Data.SLOTS.size() - 1)]
	var item: Dictionary = Data.generate_item(slot, lvl, rng)
	var idesc: String = "%s — %s" % [item.get("rarity_name", ""), Data.bonus_summary(item["bonus"])]
	if item.get("desc", "") != "":
		idesc += " — " + String(item["desc"])
	rewards.append({ "type": "equip", "data": item, "color": item.get("rarity_color", Color.WHITE),
		"label": "%s %s" % [Data.SLOT_GLYPH[slot], item["name"]],
		"desc": idesc })
	var amt: int = (8 + floor_num * 3) * (2 if is_elite else 1)
	rewards.append({ "type": "shards", "value": amt, "color": Color(1.0, 0.85, 0.35),
		"label": "✦ %d Éclats" % amt,
		"desc": "Monnaie pour la boutique et le Sanctuaire." })
	# Bonus d'élite : un parchemin de compétence si possible, sinon un consommable.
	if is_elite:
		var sid: String = _pick_droppable_skill()
		if sid != "":
			rewards.append({ "type": "skill", "data": sid, "color": Data.skill_rarity_color(sid),
				"label": "✦ Parchemin — %s" % Data.SKILLS[sid]["name"],
				"desc": String(Data.SKILLS[sid]["desc"]) })
		else:
			rewards.append(_consumable_reward())
	return rewards

func _consumable_reward() -> Dictionary:
	var c: Dictionary = Data.generate_consumable(floor_num, rng)
	return { "type": "consumable", "data": c, "color": c.get("color", Color.WHITE),
		"label": "! %s" % c["name"], "desc": "Objet à usage unique." }

func resolve_floor_reward(idx: int) -> void:
	if idx < 0 or idx >= pending_rewards.size():
		return
	var r: Dictionary = pending_rewards[idx]
	match String(r["type"]):
		"heal":
			var amt: int = int(round(player.max_hp * float(r["value"])))
			player.heal(amt)
			add_message("[color=#7aff8a]Récompense : +%d PV.[/color]" % amt)
		"shards":
			run_shards += int(r["value"])
			add_message("[color=#ffd24a]Récompense : +%d Éclats.[/color]" % int(r["value"]))
		"equip":
			_bag_add(r["data"])
		"consumable":
			_bag_add(r["data"])
		"skill":
			_acquire_skill(String(r["data"]))
	pending_rewards = []
	_advance()

func _boss_alive() -> bool:
	for e in enemies:
		if e.is_boss and e.is_alive():
			return true
	return false

# --- Génération d'un combat (combat / élite / boss) ---------------------------
func generate_floor(node_type: String = "combat") -> void:
	first_strike_used = false
	_forest_fire_warned = false
	player.clear_statuses()
	var msize: Vector2i = Data.random_map_size(rng)
	dungeon = Dungeon.new(msize.x, msize.y, rng, Data.biome_for_floor(floor_num))
	var biome_id: String = str(dungeon.biome.get("id", ""))
	if biome_id != _last_timeline_biome:
		_last_timeline_biome = biome_id
		_push_timeline("Étage %d — %s" % [floor_num, str(dungeon.biome.get("name", ""))])
	player.x = dungeon.start.x
	player.y = dungeon.start.y
	player.energy = Entity.ACTION_COST   # le joueur agit en premier
	dungeon.reveal(player.pos(), player.vision)

	enemies.clear()
	loot.clear()
	hazards.clear()
	var occupied: Array = [dungeon.start, dungeon.stairs]
	var is_boss: bool = node_type == "boss"
	# Serment d'Élite : tout combat hors boss devient une salle d'élite.
	var is_elite: bool = node_type == "elite" or (has_oath("elite") and not is_boss)

	# Le peuplement s'adapte à la taille de la carte (exploration jamais vide).
	var area: int = dungeon.width * dungeon.height
	var count: int = clampi(3 + floor_num + int(area / 2200), 5, 30)
	if is_elite:
		count = mini(count + 3, 34)
	if has_oath("horde"):        # Serment de la Horde : +50% d'ennemis
		count = mini(int(round(count * 1.5)), 40)
	for p in dungeon.random_floor_tiles(count, rng, occupied):
		var e: Entity = _make_enemy(_pick_enemy_def(), floor_num, p)
		if is_elite:
			e.max_hp = int(e.max_hp * 1.25)
			e.hp = e.max_hp
			e.atk = int(e.atk * 1.2)
			e.ai["smart_path"] = true
		elif not is_boss and rng.randf() < _legendary_chance():
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
			var bdef: Dictionary = _pick_boss_def()
			var boss: Entity = _make_enemy(bdef, floor_num, boss_spots[0], true)
			boss.ai["smart_path"] = true
			enemies.append(boss)
			occupied.append(boss_spots[0])
			_boss_on_spawn(boss, occupied)
			add_message("[color=#ff6464]⚠ %s t'attend ! Vaincs-le pour ouvrir l'escalier.[/color]" % boss.display_name)
		else:
			add_message("[color=#ff6464]⚠ Le GARDIEN de la strate t'attend ![/color]")
	elif is_elite:
		add_message("[color=#ff9a64]☠ Salle d'élite : ennemis renforcés, meilleur butin.[/color]")

	var loot_count: int = mini(rng.randi_range(1, 3) + int(area / 9000) + (1 if is_elite else 0), 14)
	for p in dungeon.random_floor_tiles(loot_count, rng, occupied):
		occupied.append(p)
		_spawn_loot(p, is_elite)

	_maybe_spawn_poi(occupied)

	# Œil du Devin : dévoile l'emplacement du butin à travers le brouillard.
	map_view.reveal_loot = GameState.reveals_loot()
	if map_view.reveal_loot:
		for item in loot:
			dungeon.mark_explored(item["pos"])

	refresh()        # règle map_view.dungeon, le brouillard et la caméra

## Probabilité qu'un monstre soit légendaire (porteur de pouvoir), ×4 avec Chasseur.
func _legendary_chance() -> float:
	return LEGENDARY_CHANCE * (4.0 if GameState.legendary_boost() else 1.0)

## Boss de la strate courante (sélection cyclique parmi Data.BOSSES).
func _pick_boss_def() -> Dictionary:
	if Data.BOSSES.is_empty():
		return Data.BOSS
	return Data.BOSSES[map_act % Data.BOSSES.size()]

## À l'apparition d'un boss : crée ses gardiens liés (âmes-boucliers, chaudrons)
## qui le protègent tant qu'ils vivent (cf. _living_guardians + _player_attack).
func _boss_on_spawn(boss: Entity, occupied: Array) -> void:
	var g: Dictionary = boss.ai.get("guardians", {})
	if g.is_empty():
		return
	var count: int = int(g.get("count", 3))
	var spr: String = String(g.get("sprite", "ame"))
	for sp in dungeon.random_floor_tiles_near(boss.pos(), 6, count, rng, occupied):
		var gd := Entity.new()
		gd.display_name = "Chaudron" if spr == "chaudron" else "Âme-bouclier"
		gd.glyph = "*"
		gd.sprite = spr
		gd.color = boss.color
		gd.faction = Entity.Faction.ENEMY
		gd.max_hp = maxi(8, int(boss.max_hp * 0.18))
		gd.hp = gd.max_hp
		gd.atk = 0
		gd.defense = 0
		gd.speed = 1
		gd.shard_value = 2
		gd.x = sp.x
		gd.y = sp.y
		gd.ai = { "behavior": "stationary", "guard_for": boss.get_instance_id() }
		enemies.append(gd)
		occupied.append(sp)
	add_message("[color=#c8b0ff]%s est protégé par %d gardien(s) — détruis-les pour le rendre vulnérable ![/color]" % [boss.display_name, count])

## Nombre de gardiens encore en vie liés à ce boss.
func _living_guardians(boss: Entity) -> int:
	var n: int = 0
	var bid: int = boss.get_instance_id()
	for e in enemies:
		if e.is_alive() and int(e.ai.get("guard_for", 0)) == bid:
			n += 1
	return n

## Dieu-Bête : bascule de phase selon les PV (distance -> mêlée -> zone).
func _boss_update_phase(e: Entity) -> void:
	var ratio: float = float(e.hp) / float(maxi(1, e.max_hp))
	var phase: int = 1 if ratio > 0.66 else (2 if ratio > 0.33 else 3)
	if int(e.ai.get("phase", 0)) == phase:
		return
	e.ai["phase"] = phase
	match phase:
		1:
			e.ai["behavior"] = "ranged"
		2:
			e.ai["behavior"] = "charger"
			e.atk = int(round(e.atk * 1.2))
			add_message("[color=#ff6a40]%s — Phase II : l'arène se resserre, assaut furieux ![/color]" % e.display_name)
		3:
			e.ai["behavior"] = "caster"
			add_message("[color=#c8b0ff]%s — Phase III : invocations désespérées ![/color]" % e.display_name)

func _pick_enemy_def() -> Dictionary:
	var pool: Array = []
	for def in Data.ENEMIES:
		if def["min_floor"] > floor_num:
			continue
		# Phase 5.2 : les espèces faibles se retirent au lieu de scaler à l'infini.
		if def.has("max_floor") and floor_num > int(def["max_floor"]):
			continue
		pool.append(def)
	if pool.is_empty():
		pool = [Data.ENEMIES[0]]
	return pool[rng.randi_range(0, pool.size() - 1)]

## Crée un ennemi (ou un boss si is_boss) à partir d'une définition, scalé par l'étage.
func _make_enemy(def: Dictionary, floor: int, p: Vector2i, is_boss: bool = false) -> Entity:
	var e := Entity.new()
	# Phase 5.2 : pentes d'échelle SÉPARÉES par stat (PV / ATK / DEF) — leviers
	# d'équilibrage distincts, tous dans Data.gd. La Défense est désormais scalée.
	var step: float = float(floor - 1)
	var hp_scale: float = 1.0 + step * (Data.BOSS_HP_SLOPE if is_boss else Data.ENEMY_HP_SLOPE)
	var atk_scale: float = 1.0 + step * (Data.BOSS_ATK_SLOPE if is_boss else Data.ENEMY_ATK_SLOPE)
	var def_scale: float = 1.0 + step * (Data.BOSS_DEF_SLOPE if is_boss else Data.ENEMY_DEF_SLOPE)
	e.display_name = def["name"]
	e.glyph = def["glyph"]
	e.sprite = def.get("sprite", "boss" if is_boss else "")
	e.color = def["color"]
	e.faction = Entity.Faction.ENEMY
	e.is_boss = is_boss
	e.max_hp = int(round(def["max_hp"] * hp_scale))
	e.hp = e.max_hp
	e.atk = int(round(def["atk"] * atk_scale))
	e.defense = int(round(int(def.get("defense", 0)) * def_scale))
	e.speed = int(def.get("speed", 100))
	e.shard_value = def["shards"]
	# Phase 5.2 : l'XP est découplée des Éclats (champ "xp" explicite, par défaut
	# égal aux Éclats). Permet de régler la courbe de niveau sans toucher l'économie.
	e.xp_value = int(def.get("xp", def["shards"]))
	e.x = p.x
	e.y = p.y
	e.energy = rng.randi_range(0, Entity.ACTION_COST - 1)
	# IA / traits data-driven (copie profonde : chaque ennemi a son propre état).
	e.ai = def.get("ai", {}).duplicate(true)
	e.hp_regen = int(def.get("hp_regen", 0))
	# Drake : souffle de feu en zone chaude (volcan/désert), d'acide ailleurs.
	if e.ai.get("elemental", false):
		var bid: String = str(dungeon.biome.get("id", "plaine")) if dungeon != null else "plaine"
		if bid == "volcan" or bid == "desert":
			e.ai["on_hit"] = { "id": "burn", "turns": 3, "value": maxf(2.0, e.atk * 0.4) }
		else:
			e.ai["on_hit"] = { "id": "weaken", "turns": 3, "value": 3.0 }
	# Mimic : déguisé en coffre jusqu'à ce que l'héroïne approche.
	if e.ai.get("behavior", "") == "ambush":
		e.sprite = "coffre"
	if is_boss:
		e.hp_regen = maxi(e.hp_regen, 3)   # le Gardien se régénère : combat d'usure
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

## Structure de point d'intérêt rare (une par biome) : dressing décoratif posé
## sur un carré 2x2 praticable et libre, avec un coffre au butin garanti et
## nettement meilleur en son sein. Purement additif — si aucun emplacement
## valide n'est trouvé, on l'ignore simplement (c'est voulu rare).
func _maybe_spawn_poi(occupied: Array) -> void:
	var poi: Dictionary = dungeon.biome.get("poi", {})
	if poi.is_empty() or rng.randf() >= POI_CHANCE:
		return
	var styles: Array = dungeon.biome.get("decor_styles", [])
	if styles.is_empty():
		return
	for a in dungeon.random_floor_tiles(10, rng, occupied):
		var cells: Array = [a, a + Vector2i(1, 0), a + Vector2i(0, 1), a + Vector2i(1, 1)]
		var ok := true
		for cp in cells:
			if not dungeon.is_walkable(cp.x, cp.y) or occupied.has(cp) or dungeon.decor[cp.y][cp.x] != "":
				ok = false
				break
		if not ok:
			continue
		dungeon.decor[a.y][a.x] = String(poi["structure"])
		var dressing: Array = poi.get("dressing", [0, 1])
		var d0: int = int(dressing[0])
		var d1: int = int(dressing[1]) if dressing.size() > 1 else d0
		dungeon.decor[cells[1].y][cells[1].x] = Data.biome_decor_sprite(dungeon.biome["id"], d0)
		dungeon.decor[cells[2].y][cells[2].x] = Data.biome_decor_sprite(dungeon.biome["id"], d1)
		for cp in cells:
			occupied.append(cp)
		_spawn_poi_chest(cells[3])
		add_message("[color=#ffd24a]✦ %s repéré non loin…[/color]" % String(poi.get("name", "Un lieu mystérieux")))
		return

## Coffre de POI : butin garanti, nettement meilleur qu'un coffre normal
## (niveau virtuel +6, chance d'artefact augmentée). Toujours affiché comme
## un coffre au sol, ramassé en marchant dessus (cf. _pickup_loot_at).
func _spawn_poi_chest(p: Vector2i) -> void:
	var adef: Dictionary = {}
	if rng.randf() < 0.25:
		adef = _pick_artifact_def()
	if not adef.is_empty():
		loot.append({ "pos": p, "kind": "artifact", "glyph": Data.ARTIFACT_GLYPH,
			"sprite": "coffre", "color": adef["color"], "data": adef })
	else:
		var lvl: int = floor_num + 6
		var slot: String = Data.SLOTS[rng.randi_range(0, Data.SLOTS.size() - 1)]
		var item: Dictionary = Data.generate_item(slot, lvl, rng)
		loot.append({ "pos": p, "kind": "equip", "glyph": Data.SLOT_GLYPH[slot],
			"sprite": "coffre", "color": item["rarity_color"], "data": item })

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
	map_view.base_position = Vector2(round(-cam_x), round(-cam_y))

# --- Entrées clavier ----------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if state == State.INVENTORY:
		if event.is_action_pressed("inventory") or event.is_action_pressed("cancel"):
			close_inventory()
		return
	# Navigation clavier dans les écrans de menu (Échap = revenir en arrière,
	# vers le Hub ou l'écran-titre selon d'où l'écran a été ouvert).
	if state == State.LOADOUT or state == State.META:
		if event.is_action_pressed("cancel"):
			return_to_previous()
		return
	if state == State.GAMEOVER:
		var k: int = event.keycode
		if event.is_action_pressed("cancel") or k == KEY_ENTER or k == KEY_KP_ENTER:
			return_to_title()
		return
	if state == State.HUB:
		# Le déplacement est géré en polling dans _process (répétition fluide) ;
		# seul "cancel" (ponctuel) reste géré par événement ici.
		if event.is_action_pressed("cancel"):
			return_to_title()
		return
	if state == State.PAUSED:
		if event.is_action_pressed("cancel"):
			close_pause()
		return
	if state != State.PLAYING:
		return
	# Le déplacement est géré en polling dans _process (cf. plus bas) : appui
	# immédiat + répétition après un délai, plus réactif qu'un flux d'événements.
	if event.is_action_pressed("wait"):
		pass_turn()
	elif event.is_action_pressed("ability"):
		use_ability()
	elif event.is_action_pressed("inventory"):
		open_inventory()
	elif event.is_action_pressed("cancel"):
		open_pause()

## Polling du mouvement (PLAYING et HUB) : appui immédiat, puis répétition
## après REPEAT_INITIAL_DELAY à la cadence REPEAT_RATE tant que la touche est
## maintenue. Au plus UN pas par frame (évite un double-pas si deux touches de
## direction sont maintenues ensemble).
func _process(_delta: float) -> void:
	if state != State.PLAYING and state != State.HUB:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	for pair in [["move_up", Vector2i(0, -1)], ["move_down", Vector2i(0, 1)],
			["move_left", Vector2i(-1, 0)], ["move_right", Vector2i(1, 0)]]:
		var action: String = pair[0]
		var dir: Vector2i = pair[1]
		if Input.is_action_just_pressed(action):
			_move_in_state(dir)
			_repeat_at = now + REPEAT_INITIAL_DELAY
			break
		elif Input.is_action_pressed(action) and now >= _repeat_at:
			_move_in_state(dir)
			_repeat_at = now + REPEAT_RATE
			break

func _move_in_state(dir: Vector2i) -> void:
	if state == State.HUB:
		_hub_try_move(dir.x, dir.y)
	elif state == State.PLAYING:
		try_move(dir.x, dir.y)

## Met le run en pause (overlay Reprendre/Options/Abandonner).
func open_pause() -> void:
	state = State.PAUSED
	hud.show_pause()

## Referme la pause et reprend le run là où il en était.
func close_pause() -> void:
	state = State.PLAYING
	hud.hide_overlay()
	refresh()

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
	# Confusion (Fée corrompue) : une fois sur deux, le mouvement part de travers.
	if (dx != 0 or dy != 0) and player.has_status("confusion") and rng.randf() < 0.5:
		var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		var nd: Vector2i = dirs[rng.randi_range(0, 3)]
		dx = nd.x
		dy = nd.y
		add_message("[color=#d9a8ff]Désorientée, tu pars de travers ![/color]")
	if dx != 0 or dy != 0:
		player.facing = Vector2i(dx, dy)        # oriente le sprite (attaque ou déplacement)
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
		_trigger_hazard_at(player.pos())
		if not player.is_alive():
			game_over()
			return
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
	var skill: Dictionary = Data.SKILLS[player.ability_id]
	_attack_dmg_type = "magic" if String(skill.get("wtype", "melee")) == "magic" else "phys"
	_attack_elem = String(skill.get("elem", ""))
	_conducted_cells.clear()
	var cast_ok: bool = _cast_skill(skill)
	_attack_dmg_type = "phys"
	_attack_elem = ""
	if not cast_ok:
		add_message("[color=#888888]Aucune cible à portée.[/color]")
		refresh()
		return
	# Talent Écho Arcanique (Phase 6.1) : 15% de ne pas consommer la recharge.
	if player.has_talent_hook("echo_arcanique") and rng.randf() < 0.15:
		add_message("[color=#c8b0ff]✦ Écho arcanique : capacité toujours prête ![/color]")
	else:
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
			if player.ability_id == "fireball":
				ignite_area(center, int(skill.get("radius", 1)))
			return true
		"pierce":
			var tp: Entity = _nearest_enemy_in_range(rng_tiles)
			if tp == null: return false
			# Talent Balistique (Phase 6.1) : +2 de portée de transpercement.
			var pierce_rng: int = rng_tiles + (2 if player.has_talent_hook("balistique") else 0)
			return pierce_attack(player.pos(), _cardinal_to(tp.pos()), dmg, "%s transperce" % name, pierce_rng) > 0
		"bounce", "chain":
			var tb: Entity = _nearest_enemy_in_range(rng_tiles)
			if tb == null: return false
			# Talent Balistique (Phase 6.1) : +1 rebond.
			var bounces: int = int(skill.get("bounces", 3)) + (1 if player.has_talent_hook("balistique") else 0)
			return bounce_attack(tb, dmg, bounces, "%s rebondit" % name, 0.85, maxi(rng_tiles, 6)) > 0
		"push_strike":
			var tk: Entity = _nearest_enemy_in_range(rng_tiles)
			if tk == null: return false
			var pdir: Vector2i = _cardinal_to(tk.pos())
			_player_attack(tk, dmg, "%s percute" % name)
			if tk.is_alive():
				push_entity(tk, pdir, int(skill.get("push", 2)), true)
			return true
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
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				ignite(target.pos() + d)
		"poison":
			apply_poison(target, turns, maxf(1.0, round(float(dmg) * float(skill.get("val", 0.3)))))
			add_message("[color=#9fdf6a]%s est empoisonné.[/color]" % target.display_name)

func _nearest_enemy_in_range(rng_tiles: int) -> Entity:
	var best: Entity = null
	var best_d: int = 999999
	for e in enemies:
		if not e.is_alive():
			continue
		if not dungeon.is_visible(e.x, e.y):
			continue        # fog
		if e.ai.get("behavior", "") == "ambush" and not e.revealed:
			continue        # mimic non démasqué
		if not dungeon.has_los(player.pos(), e.pos()):
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
		if not e.is_alive() or _chebyshev(center, e.pos()) > radius:
			continue
		# À bout portant (rayon 1), les murs n'arrêtent pas le souffle ; au-delà,
		# la ligne de vue doit être dégagée.
		if radius >= 2 and not dungeon.has_los(center, e.pos()):
			continue
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

## Projection (Phase 4.3) : pousse `target` (joueuse ou ennemi) de `tiles`
## cases dans `dir`. Chaque case rencontrée applique sa règle : entité →
## collision (2 dégâts chacun, stop) ; lave (volcan) → brûlure sévère, la
## cible est repoussée sur sa case d'origine ; eau → 3 dégâts + ralenti, stop
## au bord ; glace → glisse (1 case bonus) ; piège → se déclenche contre la
## cible poussée ; mur/arbre/rocher → stop net.
func push_entity(target: Entity, dir: Vector2i, tiles: int, by_player: bool = false) -> void:
	if dir == Vector2i.ZERO or target == null or not target.is_alive() or dungeon == null:
		return
	# Talent Démolisseur (Phase 6.1) : les poussées de la joueuse gagnent +1 case
	# et +3 dégâts environnementaux/de collision contre l'entité poussée.
	var demo: bool = by_player and player != null and player.has_talent_hook("demolisseur")
	var push_bonus: int = 3 if demo else 0
	var remaining: int = tiles + (1 if demo else 0)
	var slid: bool = false
	while remaining > 0:
		remaining -= 1
		var next: Vector2i = target.pos() + dir
		if next.x <= 0 or next.x >= dungeon.width - 1 or next.y <= 0 or next.y >= dungeon.height - 1:
			break
		var occupant: Entity = _entity_at(next)
		if occupant != null and occupant != target:
			# Collision : les deux encaissent.
			if target == player:
				last_damage_source = "une collision avec %s" % occupant.display_name
			target.take_damage(2)
			occupant.take_damage(2 + push_bonus)
			add_message("[color=#ffb86a]Collision : %s et %s encaissent (-2 chacun).[/color]" %
				["toi" if target == player else target.display_name,
				 "toi" if occupant == player else occupant.display_name])
			if occupant != player and not occupant.is_alive():
				on_enemy_killed(occupant)
			break
		if dungeon.tiles[next.y][next.x] == Dungeon.WATER and dungeon.effects[next.y][next.x] != Dungeon.EFF_FROZEN:
			if dungeon.is_lava():
				# Lave : morsure ardente, la cible rebondit sur sa case d'origine.
				if target == player:
					last_damage_source = "la lave"
				target.take_damage(8 + floor_num + push_bonus)
				apply_burn(target, 3, 3.0)
				add_message("[color=#ff8a4a]La lave mord %s ![/color]" %
					("ta chair" if target == player else target.display_name))
			else:
				# Eau : reste sur la dernière case valide, trempé et ralenti.
				if target == player:
					last_damage_source = "l'eau glacée"
				target.take_damage(3 + push_bonus)
				apply_slow(target, 2, 0.4)
				add_message("[color=#9fdfff]%s au bord de l'eau, trempé et ralenti.[/color]" %
					("Tu vacilles" if target == player else "%s vacille" % target.display_name))
			break
		if not dungeon.is_walkable(next.x, next.y):
			break                              # mur / arbre / rocher : stop net
		target.x = next.x
		target.y = next.y
		if dungeon.effects[next.y][next.x] == Dungeon.EFF_FROZEN and not slid:
			slid = true
			remaining += 1                     # glace : glisse une case de plus
		_trigger_hazard_at(target.pos(), target)   # les pièges coupent enfin dans les deux sens
		if not target.is_alive():
			break
	if target == player:
		_check_revive()
		if player.is_alive():
			_pickup_loot_at(player.pos())
	elif not target.is_alive():
		on_enemy_killed(target)

## Cible du prochain saut de rebond/chaîne : mêmes filtres de visibilité que
## _nearest_enemy_in_range, SAUF la ligne de vue (magie arquée entre les sauts
## : on ignore volontairement has_los) — la cible du saut doit rester visible.
func _nearest_enemy_excluding(from: Vector2i, rng_tiles: int, exclude: Dictionary) -> Entity:
	var best: Entity = null
	var best_d: int = 999999
	for e in enemies:
		if not e.is_alive() or exclude.has(e.get_instance_id()):
			continue
		if not dungeon.is_visible(e.x, e.y):
			continue        # fog
		if e.ai.get("behavior", "") == "ambush" and not e.revealed:
			continue        # mimic non démasqué
		var d: int = _chebyshev(from, e.pos())
		if d <= rng_tiles and d < best_d:
			best_d = d
			best = e
	return best

# --- Statuts : application (utilisés par compétences/pouvoirs) -----------------
## La joueuse subit-elle un dégât-sur-la-durée ? (talent Berserker, Phase 6.1)
func _player_has_dot() -> bool:
	return player != null and (player.has_status("poison") or player.has_status("burn")
		or player.has_status("bleed") or player.has_status("disease"))

func apply_poison(target: Entity, turns: int, dmg_per_turn: float, max_stacks: int = 10) -> void:
	var v: float = dmg_per_turn
	# Talent Toxicologue (Phase 6.1) : ×1.6 sur les poisons que la joueuse inflige
	# aux ennemis (les statuts ne tracent pas leur applicant — v1 honnête : on
	# gate sur « cible ennemie » pour ne jamais amplifier un poison subi).
	if target.faction == Entity.Faction.ENEMY and player != null and player.has_talent_hook("toxicologue"):
		v *= 1.6
	target.add_status("poison", turns, v, max_stacks)

func apply_burn(target: Entity, turns: int, dmg_per_turn: float, max_stacks: int = 5) -> void:
	if not target.ai.is_empty() and target.ai.get("immune_fire", false):
		return                                   # Élémentaire de feu : insensible au feu
	# Talent Pyromane (Phase 6.1) : +1 palier de brûlure max sur les cibles ennemies.
	if target.faction == Entity.Faction.ENEMY and player != null and player.has_talent_hook("pyromane"):
		max_stacks += 1
	var v: float = dmg_per_turn
	var wf: float = float(target.ai.get("weak_fire", 0.0)) if not target.ai.is_empty() else 0.0
	if wf > 0.0:
		v *= 1.0 + wf
	target.add_status("burn", turns, v, max_stacks)

func apply_slow(target: Entity, turns: int, pct: float) -> void:
	target.add_status("slow", turns, pct)

func apply_stun(target: Entity, turns: int) -> void:
	target.add_status("stun", turns)

func apply_bleed(target: Entity, turns: int, dmg_per_turn: float, max_stacks: int = 8) -> void:
	target.add_status("bleed", turns, dmg_per_turn, max_stacks)

func apply_disease(target: Entity, turns: int, dmg_per_turn: float, max_stacks: int = 6) -> void:
	target.add_status("disease", turns, dmg_per_turn, max_stacks)

func apply_weaken(target: Entity, turns: int, amount: float) -> void:
	target.add_status("weaken", turns, amount)

func apply_confuse(target: Entity, turns: int) -> void:
	target.add_status("confusion", turns)

# --- Terrain élémentaire (Phase 4) --------------------------------------------
## Embrase un ARBRE (case TREE, sans effet en cours). Renvoie false si la case
## n'était pas éligible (hors bordure, pas un arbre, déjà en feu/calcinée...).
func ignite(p: Vector2i) -> bool:
	if dungeon == null:
		return false
	if p.x <= 0 or p.x >= dungeon.width - 1 or p.y <= 0 or p.y >= dungeon.height - 1:
		return false
	# Le feu (quel qu'il soit) fait fondre instantanément une case gelée.
	if dungeon.effects[p.y][p.x] == Dungeon.EFF_FROZEN:
		_melt_at(p)
		return false
	if dungeon.tiles[p.y][p.x] != Dungeon.TREE:
		return false
	if dungeon.effects[p.y][p.x] != Dungeon.EFF_NONE:
		return false
	dungeon.effects[p.y][p.x] = Dungeon.EFF_BURNING
	dungeon.effect_timer[p.y][p.x] = 4
	dungeon.active_effects.append(p)
	if not _forest_fire_warned:
		_forest_fire_warned = true
		add_message("[color=#ff8a4a]Le feu prend dans les frondaisons.[/color]")
		Sfx.play("danger")
	return true

## Ignite tous les arbres dans un rayon (Chebyshev) autour d'un centre —
## utilisé par les explosions/zones de feu (boule de feu, mort de l'Élémentaire
## de feu, sacrifice du Cultiste...).
func ignite_area(center: Vector2i, radius: int) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if maxi(absi(dx), absi(dy)) <= radius:
				ignite(center + Vector2i(dx, dy))

## Réactions élémentaires de terrain (Phase 4.2) : déclenchées quand une
## compétence taguée "elem" touche une cible. La foudre conduit dans l'eau,
## le givre gèle l'eau ; le feu passe déjà par ignite()/ignite_area().
func _elemental_reaction(center: Vector2i, dealt: int) -> void:
	if dungeon == null:
		return
	match _attack_elem:
		"lightning": conduct_lightning(center, dealt)
		"frost": freeze_water_near(center)

## Foudre conduite : si `center` (case de la cible touchée) est 4-adjacente à
## un plan d'eau (pas de la lave, pas de la glace), tout ENNEMI vivant autre
## que la cible et 4-adjacent au même plan d'eau prend 50% des dégâts du coup.
## Un plan d'eau donné ne conduit qu'UNE fois par lancer (_conducted_cells) —
## une chaîne d'éclairs ne re-déclenche pas la même décharge à chaque saut.
func conduct_lightning(center: Vector2i, dealt: int) -> void:
	if dungeon.is_lava() or dealt <= 0:
		return
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var wp: Vector2i = center + d
		if wp.x < 0 or wp.x >= dungeon.width or wp.y < 0 or wp.y >= dungeon.height:
			continue
		if dungeon.tiles[wp.y][wp.x] != Dungeon.WATER:
			continue
		if dungeon.effects[wp.y][wp.x] == Dungeon.EFF_FROZEN:
			continue                       # la glace n'est plus conductrice
		if _conducted_cells.has(wp):
			continue                       # plan d'eau déjà déchargé ce lancer
		var body: Array = dungeon.water_body(wp, 500)
		var body_set: Dictionary = {}
		for c in body:
			body_set[c] = true
			_conducted_cells[c] = true
		var arc: int = maxi(1, int(round(dealt * Data.LIGHTNING_CONDUCT_PCT)))
		var zapped: int = 0
		for e in enemies.duplicate():
			if not e.is_alive() or e.pos() == center:
				continue
			var near_water: bool = false
			for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if body_set.has(e.pos() + dd):
					near_water = true
					break
			if not near_water:
				continue
			var dz: int = e.take_damage(arc)
			zapped += 1
			if map_view != null:
				map_view.fx_hit(e)
				map_view.fx_damage(e.pos(), dz, "hit")
			if not e.is_alive():
				on_enemy_killed(e)
		if zapped > 0:
			add_message("[color=#9fdfff]⚡ La foudre crépite le long du rivage (%d touché(s), -%d).[/color]" % [zapped, arc])
		return                             # une seule conduction par coup

## Gel : fige en glace praticable les cases du plan d'eau adjacent à `center`,
## dans un rayon Chebyshev FROST_FREEZE_RADIUS de l'impact, pour FROZEN_TURNS
## actions de la joueuse. Sans effet sur la lave (volcan).
func freeze_water_near(center: Vector2i) -> void:
	if dungeon == null or dungeon.is_lava():
		return
	var frozen: int = 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var wp: Vector2i = center + d
		if wp.x < 0 or wp.x >= dungeon.width or wp.y < 0 or wp.y >= dungeon.height:
			continue
		if dungeon.tiles[wp.y][wp.x] != Dungeon.WATER:
			continue
		for c in dungeon.water_body(wp, 500):
			if _chebyshev(c, center) > Data.FROST_FREEZE_RADIUS:
				continue
			if dungeon.effects[c.y][c.x] != Dungeon.EFF_NONE:
				continue
			dungeon.effects[c.y][c.x] = Dungeon.EFF_FROZEN
			dungeon.effect_timer[c.y][c.x] = Data.FROZEN_TURNS
			dungeon.active_effects.append(c)
			frozen += 1
	if frozen > 0:
		add_message("[color=#9fdfff]❄ L'eau se fige en un pont de glace (%d case(s)).[/color]" % frozen)
		dungeon.rebuild_reachability()

## Fonte d'une case gelée : l'eau redevient infranchissable ; une entité qui
## se tenait sur la glace est relogée sur la case praticable la plus proche
## (3 dégâts + ralentissement — « la glace cède ! »).
func _melt_at(p: Vector2i, rebuild: bool = true) -> void:
	if dungeon.effects[p.y][p.x] != Dungeon.EFF_FROZEN:
		return
	dungeon.effects[p.y][p.x] = Dungeon.EFF_NONE
	dungeon.effect_timer[p.y][p.x] = 0
	var ent: Entity = _entity_at(p)
	if ent != null and ent.is_alive():
		# Reloge sur de la terre ferme (jamais WATER, même gelée : la glace
		# voisine peut fondre dans la même passe et relogerait en chaîne).
		var spot: Vector2i = NO_TILE
		for radius in range(1, 5):
			for dy in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					var np: Vector2i = p + Vector2i(dx, dy)
					if np.x < 0 or np.x >= dungeon.width or np.y < 0 or np.y >= dungeon.height:
						continue
					if dungeon.tiles[np.y][np.x] == Dungeon.WATER:
						continue
					if dungeon.is_walkable(np.x, np.y) and _entity_at(np) == null:
						spot = np
						break
				if spot != NO_TILE:
					break
			if spot != NO_TILE:
				break
		if spot == NO_TILE:
			spot = dungeon.start
		ent.x = spot.x
		ent.y = spot.y
		if ent == player:
			last_damage_source = "la glace qui cède"
		ent.take_damage(3)
		apply_slow(ent, 2, 0.4)
		add_message("[color=#9fdfff]La glace cède sous %s ![/color]" % ("tes pas" if ent == player else ent.display_name))
		if ent == player:
			_check_revive()
		elif not ent.is_alive():
			on_enemy_killed(ent)
	if rebuild:
		dungeon.rebuild_reachability()

## Nuage toxique (marais) : laissé à la mort de certaines créatures (ai.death_cloud).
## Empoisonne les entités qui s'y attardent, se dissipe après CLOUD_TURNS.
func spawn_poison_cloud(center: Vector2i, radius: int = 1, turns: int = -1) -> void:
	if dungeon == null:
		return
	if turns < 0:
		turns = Data.CLOUD_TURNS
	var placed: int = 0
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var p: Vector2i = center + Vector2i(dx, dy)
			if p.x <= 0 or p.x >= dungeon.width - 1 or p.y <= 0 or p.y >= dungeon.height - 1:
				continue
			var t: int = dungeon.tiles[p.y][p.x]
			if t != Dungeon.FLOOR and t != Dungeon.ROAD:
				continue
			if dungeon.effects[p.y][p.x] != Dungeon.EFF_NONE:
				continue
			dungeon.effects[p.y][p.x] = Dungeon.EFF_CLOUD
			dungeon.effect_timer[p.y][p.x] = turns
			dungeon.active_effects.append(p)
			placed += 1
	if placed > 0:
		add_message("[color=#9fdf6a]Un nuage toxique s'échappe de la dépouille.[/color]")

## Fait avancer la couche d'effets de terrain d'un cran — appelé une fois par
## action du joueur (le terrain vit au rythme du joueur, avant que les
## ennemis n'agissent). Ne parcourt QUE active_effects, jamais la grille
## entière (640x400 cases existent sur les grandes cartes).
func _tick_terrain() -> void:
	if dungeon == null or dungeon.active_effects.is_empty():
		return
	var reach_dirty := false
	# Duplique : ignite() ci-dessous ajoute à dungeon.active_effects (propagation) —
	# itérer directement sur le tableau source ferait aussi traiter les cases
	# fraîchement embrasées dans cette même passe.
	for p in dungeon.active_effects.duplicate():
		var eff: int = dungeon.effects[p.y][p.x]
		if eff == Dungeon.EFF_BURNING:
			dungeon.effect_timer[p.y][p.x] -= 1
			# Dégâts à toute entité (joueur inclus) dans le voisinage 8-connexe.
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var np: Vector2i = p + Vector2i(dx, dy)
					var ent: Entity = _entity_at(np)
					if ent != null and ent.is_alive():
						apply_burn(ent, 2, 2.0 + floor_num * 0.2, 3)
			# Propagation : chaque arbre 4-adjacent non touché a une chance de s'embraser.
			# Talent Pyromane (Phase 6.1) : propagation à 50% au lieu de FIRE_SPREAD_CHANCE.
			var spread_chance: float = Data.FIRE_SPREAD_CHANCE
			if player != null and player.has_talent_hook("pyromane"):
				spread_chance = maxf(spread_chance, 0.50)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var np2: Vector2i = p + d
				if dungeon.tiles[np2.y][np2.x] == Dungeon.TREE and dungeon.effects[np2.y][np2.x] == Dungeon.EFF_NONE:
					if rng.randf() < spread_chance:
						ignite(np2)
			if dungeon.effect_timer[p.y][p.x] <= 0:
				dungeon.effects[p.y][p.x] = Dungeon.EFF_BURNT
				dungeon.tiles[p.y][p.x] = Dungeon.FLOOR
				dungeon.decor[p.y][p.x] = ""
				reach_dirty = true
				# EFF_BURNT reste marqué en permanence (pas de retour à EFF_NONE) :
				# c'est une trace de sol calciné, pas une case active à re-traiter.
		elif eff == Dungeon.EFF_FROZEN:
			dungeon.effect_timer[p.y][p.x] -= 1
			if dungeon.effect_timer[p.y][p.x] <= 0:
				_melt_at(p, false)
				reach_dirty = true
		elif eff == Dungeon.EFF_CLOUD:
			dungeon.effect_timer[p.y][p.x] -= 1
			var cent: Entity = _entity_at(p)
			if cent != null and cent.is_alive():
				apply_poison(cent, 2, Data.CLOUD_POISON_VAL)
				if cent == player:
					add_message("[color=#9fdf6a]Les vapeurs toxiques te rongent.[/color]")
			if dungeon.effect_timer[p.y][p.x] <= 0:
				dungeon.effects[p.y][p.x] = Dungeon.EFF_NONE
	# Purge les cases qui ne sont plus BURNING/FROZEN/CLOUD (ex: calcinées ce
	# tour) tout en conservant celles fraîchement embrasées par ignite()
	# ci-dessus — on relit dungeon.active_effects (pas la copie) pour ça.
	var still_active: Array = []   # Array[Vector2i]
	for p in dungeon.active_effects:
		var eff2: int = dungeon.effects[p.y][p.x]
		if eff2 == Dungeon.EFF_BURNING or eff2 == Dungeon.EFF_FROZEN or eff2 == Dungeon.EFF_CLOUD:
			still_active.append(p)
	dungeon.active_effects = still_active
	if reach_dirty:
		dungeon.rebuild_reachability()

## Entité (joueur ou ennemi vivant) sur une case donnée, ou null.
func _entity_at(p: Vector2i) -> Entity:
	if player != null and player.is_alive() and player.pos() == p:
		return player
	return enemy_at(p.x, p.y)

## Défense effective du joueur (réduite par le statut "weaken" des ennemis,
## augmentée par le préfixe d'armure "cuirasse" — réduction plate en plus de
## la Défense normale).
func _player_def() -> int:
	var d: int = player.defense
	if player.has_status("weaken"):
		d -= int(round(player.status_value("weaken")))
	if player.has_proc("cuirasse"):
		d += int(round(player.proc_value("cuirasse")))
	return maxi(0, d)

## Applique au joueur le statut "au contact" déclaré par un ennemi (def ai.on_hit).
func _apply_enemy_on_hit(attacker: Entity) -> void:
	var oh: Dictionary = attacker.ai.get("on_hit", {})
	if oh.is_empty() or not player.is_alive():
		return
	var id: String = String(oh.get("id", ""))
	var turns: int = int(oh.get("turns", 2))
	var val: float = float(oh.get("value", 1.0))
	match id:
		"poison": apply_poison(player, turns, maxf(1.0, val)); add_message("[color=#9fdf6a]Tu es empoisonné.[/color]")
		"bleed": apply_bleed(player, turns, maxf(1.0, val)); add_message("[color=#ff7a8a]Tu saignes.[/color]")
		"disease": apply_disease(player, turns, maxf(1.0, val)); add_message("[color=#9fdf6a]La maladie te ronge.[/color]")
		"burn": apply_burn(player, turns, maxf(1.0, val)); add_message("[color=#ff9a5a]Tu prends feu.[/color]")
		"slow": apply_slow(player, turns, val); add_message("[color=#9fdfff]Tu es ralenti.[/color]")
		"weaken": apply_weaken(player, turns, val); add_message("[color=#ffb98a]Ta défense faiblit.[/color]")
		"confusion": apply_confuse(player, turns); add_message("[color=#d9a8ff]Tu es désorienté.[/color]")
		"stun": apply_stun(player, turns); add_message("[color=#cdb8ff]Tu es paralysé.[/color]")

# --- Combat -------------------------------------------------------------------
## Attaque du JOUEUR vers un ennemi : gère critique, défense, vol de vie,
## et les procs d'objets uniques (exécution, frénésie, premier coup, frappe double).
func _player_attack(target: Entity, base_raw: int, verb: String, ignore_def: bool = false) -> void:
	var raw: float = float(base_raw)
	# Résistances de l'ennemi (data-driven via ai.resist_phys / resist_magic ;
	# une valeur négative = vulnérabilité, ex. le Golem face aux sorts).
	if not target.ai.is_empty():
		var resist: float = float(target.ai.get("resist_magic", 0.0)) if _attack_dmg_type == "magic" else float(target.ai.get("resist_phys", 0.0))
		if resist != 0.0:
			raw *= clampf(1.0 - resist, 0.05, 2.5)
	# Boss protégé par ses gardiens (âmes-boucliers / chaudrons) tant qu'ils vivent.
	if target.is_boss and target.ai.has("guardians") and _living_guardians(target) > 0:
		raw *= clampf(1.0 - float(target.ai["guardians"].get("resist", 0.85)), 0.02, 1.0)
		if rng.randf() < 0.34:
			add_message("[color=#9fb8ff]%s est protégé — détruis ses gardiens ![/color]" % target.display_name)
	# Talents mécaniques (Phase 6.1) :
	# Berserker — +25% de dégâts tant que la joueuse subit un DoT.
	if player.has_talent_hook("berserker") and _player_has_dot():
		raw *= 1.25
	# Chasseur nocturne — +10% de dégâts à distance ≥ 4 (saveur « tir à distance »).
	if player.has_talent_hook("chasseur_nuit") and _chebyshev(player.pos(), target.pos()) >= 4:
		raw *= 1.10
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
	if map_view != null:
		map_view.fx_attack(player, target.pos())
		map_view.fx_hit(target)
	Sfx.play("crit" if crit else "hit")
	var dealt: int = target.take_damage(max(1, int(round(raw)) - def))
	run_best_hit = max(run_best_hit, dealt)
	if map_view != null:
		map_view.fx_damage(target.pos(), dealt, "crit" if crit else "hit")
		if crit:
			map_view.fx_freeze(0.05)
			map_view.fx_shake(4.0)
	# Araignée Mère : pond une créature à chaque coup reçu (jusqu'à un quota).
	if target.is_boss and target.ai.has("spawn_on_hit") and target.is_alive() and target.spawned_count < int(target.ai.get("soh_max", 6)):
		var ssp: Vector2i = _free_adjacent(target.pos())
		if ssp != NO_TILE:
			var smdef: Dictionary = _enemy_def_by_sprite(String(target.ai["spawn_on_hit"]))
			if not smdef.is_empty():
				var sm: Entity = _make_enemy(smdef, floor_num, ssp)
				sm.energy = 0
				sm.awake = true
				enemies.append(sm)
				target.spawned_count += 1
				add_message("[color=#9fdf6a]%s pond une créature ![/color]" % target.display_name)
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
			if map_view != null:
				map_view.fx_damage(player.pos(), healed, "heal")
			add_message("[color=#ff7a8a]Vol de vie : +%d PV.[/color]" % healed)
	_trigger_weapon_prefixes(target)
	_elemental_reaction(target.pos(), dealt)
	if not target.is_alive():
		on_enemy_killed(target)
		return
	if player.has_proc("frappe_double") and rng.randf() < player.proc_value("frappe_double"):
		var raw2: int = int(round(base_raw * 0.5))
		var dealt2: int = target.take_damage(max(1, raw2 - target.defense))
		run_best_hit = max(run_best_hit, dealt2)
		add_message("[color=#ffb86a]Frappe double sur %s (-%d).[/color]" % [target.display_name, dealt2])
		if player.lifesteal_pct > 0.0 and dealt2 > 0:
			var healed2: int = int(ceil(dealt2 * player.lifesteal_pct))
			player.heal(healed2)
			if map_view != null:
				map_view.fx_damage(player.pos(), healed2, "heal")
		if not target.is_alive():
			on_enemy_killed(target)

## Déclenche les préfixes de combat de l'ARME équipée (façon Dungeonmans),
## indépendants des procs d'objets uniques : dégâts de feu bonus ("ardent"),
## puis chances de ralentir/empoisonner/étourdir la cible touchée. N'agit
## que sur le coup principal (pas sur la Frappe Double), comme le Venin/Vol
## de vie déjà présents.
func _trigger_weapon_prefixes(target: Entity) -> void:
	if player.has_proc("ardent") and target.is_alive():
		var fdmg: int = _fire_prefix_damage(target, player.proc_value("ardent"))
		if fdmg > 0:
			var extra: int = target.take_damage(fdmg)
			run_best_hit = max(run_best_hit, extra)
			if map_view != null:
				map_view.fx_damage(target.pos(), extra, "hit")
			add_message("[color=#ff9a5a]Brasier : %s subit -%d (feu).[/color]" % [target.display_name, extra])
		if rng.randf() < 0.25:   # (tune) chance d'embraser un arbre adjacent à la cible
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if ignite(target.pos() + d):
					break
	if not target.is_alive():
		return
	if player.has_proc("givre") and rng.randf() < player.proc_value("givre"):
		apply_slow(target, 2, 0.35)
		add_message("[color=#9fdfff]%s est ralenti par le givre.[/color]" % target.display_name)
		freeze_water_near(target.pos())   # élément givre : l'eau au contact gèle
	if player.has_proc("venimeux") and rng.randf() < player.proc_value("venimeux"):
		apply_poison(target, 3, 3.0)
		add_message("[color=#9fdf6a]%s est empoisonné par le venin.[/color]" % target.display_name)
	if player.has_proc("foudroyant") and rng.randf() < player.proc_value("foudroyant"):
		apply_stun(target, 1)
		add_message("[color=#cdb8ff]%s est étourdi par la foudre ![/color]" % target.display_name)

## Dégâts de feu instantanés bonus (préfixe "ardent") : respecte l'immunité et
## la faiblesse au feu des ennemis (mêmes règles que apply_burn).
func _fire_prefix_damage(target: Entity, avg: float) -> int:
	if avg <= 0.0 or (not target.ai.is_empty() and target.ai.get("immune_fire", false)):
		return 0
	var v: float = avg + rng.randf_range(-1.0, 1.0)
	var wf: float = float(target.ai.get("weak_fire", 0.0)) if not target.ai.is_empty() else 0.0
	if wf > 0.0:
		v *= 1.0 + wf
	return maxi(1, int(round(v)))

## Attaque d'un ENNEMI vers le joueur : gère esquive, défense (réduite par weaken),
## coups multiples (ai.atk_count), vol de vie (ai.lifesteal), statut au contact
## (ai.on_hit), épines et résurrection.
func _enemy_attack_player(attacker: Entity) -> void:
	var hits: int = maxi(1, int(attacker.ai.get("atk_count", 1)))
	var connected: bool = false
	for i in hits:
		if not attacker.is_alive() or not player.is_alive():
			return
		if _enemy_hit_player(attacker):
			connected = true
	# Le statut au contact ne s'applique qu'une fois par séquence d'attaque,
	# et seulement si au moins un coup a réellement porté (pas d'esquive totale).
	if connected:
		_apply_enemy_on_hit(attacker)

## Un coup unique d'ennemi vers le joueur. Renvoie true si le coup a porté.
func _enemy_hit_player(attacker: Entity) -> bool:
	if rng.randf() < player.dodge_chance:
		add_message("[color=#b3a8e0]Tu esquives %s ![/color]" % attacker.display_name)
		return false
	if map_view != null:
		map_view.fx_attack(attacker, player.pos())
		map_view.fx_hit(player)
	last_damage_source = attacker.display_name
	var dealt: int = player.take_damage(max(1, _enemy_atk(attacker) - _player_def()))
	if map_view != null:
		map_view.fx_damage(player.pos(), dealt, "player_hit")
	add_message("[color=#ff8a8a]%s te frappe (-%d).[/color]" % [attacker.display_name, dealt])
	var ls: float = float(attacker.ai.get("lifesteal", 0.0))
	if ls > 0.0 and dealt > 0:
		var drained: int = maxi(1, int(round(dealt * ls)))
		attacker.heal(drained)
		add_message("[color=#ff7a8a]%s te draine (+%d PV).[/color]" % [attacker.display_name, drained])
	if player.thorns_flat > 0:
		var d2: int = attacker.take_damage(player.thorns_flat)
		add_message("[color=#cdd66a]Épines : %s subit %d.[/color]" % [attacker.display_name, d2])
		if not attacker.is_alive():
			on_enemy_killed(attacker)
	_trigger_armor_retaliation(attacker, dealt)
	_check_revive()
	return true

## Préfixe d'armure "renvoi" : chance d'affaiblir l'attaquant au contact.
func _trigger_armor_retaliation(attacker: Entity, dealt: int) -> void:
	if dealt > 0 and attacker.is_alive() and player.has_proc("renvoi") and rng.randf() < player.proc_value("renvoi"):
		apply_weaken(attacker, 3, 3.0)
		add_message("[color=#ffb98a]Représailles : %s est affaibli.[/color]" % attacker.display_name)

func _check_revive() -> void:
	if player.hp <= 0 and player.revive_available():
		player.revives_used += 1
		player.hp = max(1, int(player.max_hp * 0.5))
		add_message("[color=#ffd24a]✦ Une résurrection te ramène à la vie (50% PV) ![/color]")

func on_enemy_killed(e: Entity) -> void:
	if not enemies.has(e):
		return
	Sfx.play("danger" if e.is_boss else "kill")
	run_kills += 1
	run_shards += e.shard_value
	player.xp += e.xp_value
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
	if map_view != null:
		map_view.fx_death(e)
	enemies.erase(e)
	# Explosion à la mort (Élémentaire de feu) : zone de dégâts + brûlure.
	var exp: Dictionary = e.ai.get("explode", {}) if not e.ai.is_empty() else {}
	if not exp.is_empty():
		add_message("[color=#ff8a4a]✹ %s explose en mourant ![/color]" % e.display_name)
		ignite_area(death_pos, int(exp.get("radius", 1)))
		if _chebyshev(death_pos, player.pos()) <= int(exp.get("radius", 1)):
			var ed: int = maxi(1, int(round(e.atk * float(exp.get("mult", 1.3)))) - _player_def())
			last_damage_source = "l'explosion de %s" % e.display_name
			player.take_damage(ed)
			add_message("[color=#ff8a8a]Le souffle ardent te frappe (-%d).[/color]" % ed)
			apply_burn(player, 3, maxf(1.0, e.atk * 0.3))
			_check_revive()
	# Nuage toxique à la mort (Serpent des marais, Zombie pestilentiel...).
	var cloud_chance: float = float(e.ai.get("death_cloud", 0.0)) if not e.ai.is_empty() else 0.0
	if cloud_chance > 0.0 and rng.randf() < cloud_chance:
		spawn_poison_cloud(death_pos, 1)
	if player.has_power("detonation") and _chebyshev(death_pos, player.pos()) <= 3:
		var boom: int = maxi(2, player.atk / 2 + player.ability_power)
		var hits: int = aoe_attack(death_pos, 1, boom, "Détonation frappe")
		if hits > 0:
			add_message("[color=#ff8a4a]✹ %s explose au contact de la mort.[/color]" % e.display_name)
	if e.is_boss:
		var bid: int = e.get_instance_id()
		var had_guardians: bool = false
		for g in enemies.duplicate():
			if int(g.ai.get("guard_for", 0)) == bid:
				had_guardians = true
				if map_view != null:
					map_view.fx_death(g)
				enemies.erase(g)
		if had_guardians:
			add_message("[color=#c8b0ff]Les gardiens se dissipent avec leur maître.[/color]")
		run_bosses += 1
		_push_timeline("★ Gardien vaincu : %s (Étage %d)" % [e.display_name, floor_num])
		add_message("[color=#ffd24a]★ Le Gardien tombe ! +%d Éclats. La voie est libre.[/color]" % e.shard_value)
		var reward: Dictionary = Data.generate_boss_reward(floor_num, rng)
		add_message("[color=#ffb86a]✦ Butin garanti du Gardien : %s ![/color]" % reward["name"])
		_bag_add(reward)
		_drop_skill(death_pos, true)        # le boss lâche aussi une compétence
		if run_bosses % 2 == 0:
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
			Sfx.play("pickup")
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
	var pick: String = _weighted_skill_pick(pool, weights, total)
	# Affinité Arcane : tire deux fois et garde la compétence la plus rare.
	if GameState.better_drop_pool():
		var alt: String = _weighted_skill_pick(pool, weights, total)
		if _skill_weight(alt) < _skill_weight(pick):
			pick = alt
	return pick

func _weighted_skill_pick(pool: Array, weights: Array, total: float) -> String:
	var roll: float = rng.randf() * total
	for i in pool.size():
		roll -= weights[i]
		if roll <= 0.0:
			return pool[i]
	return pool[pool.size() - 1]

## Poids de rareté d'une compétence (plus petit = plus rare).
func _skill_weight(id: String) -> float:
	var s: Dictionary = Data.SKILLS.get(id, {})
	return float(Data.SKILL_RARITIES.get(s.get("rarity", "commune"), {"weight": 999.0})["weight"])

func _acquire_skill(id: String) -> void:
	if not Data.SKILLS.has(id):
		return
	if known_skills.has(id) or String(Data.SKILLS[id]["rarity"]) == "base":
		run_shards += 8
		add_message("Compétence déjà connue : %s (+8 Éclats)." % Data.SKILLS[id]["name"])
		return
	known_skills.append(id)
	add_message("[color=#c8b0ff]✦ Compétence apprise : %s — %s[/color]" % [Data.SKILLS[id]["name"], Data.SKILLS[id]["desc"]])
	_discover("skill", id, String(Data.SKILLS[id]["name"]))
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
	if item.get("unique", false):
		_discover("unique", String(item.get("name", "")), String(item.get("name", "")))
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
			Sfx.play("heal")
			if map_view != null:
				map_view.fx_damage(player.pos(), amt, "heal")
			add_message("[color=#7aff8a]%s : +%d PV.[/color]" % [item["name"], amt])
		"heal_full":
			var full_amt: int = player.max_hp - player.hp
			player.heal(player.max_hp)
			Sfx.play("heal")
			if map_view != null:
				map_view.fx_damage(player.pos(), full_amt, "heal")
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
	_push_timeline("Ω Pouvoir obtenu : %s" % def["name"])
	_discover("power", String(def["id"]), String(def["name"]))
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
	_tick_terrain()
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
				if not player.is_alive():   # explosion à la mort peut tuer le joueur
					game_over()
					return
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
	# La régénération est suspendue tant que l'entité brûle (clé du Troll : l'enflammer).
	if e.hp_regen > 0 and not e.has_status("burn"):
		e.heal(e.hp_regen)
	var dot: int = e.tick_statuses()
	if dot > 0:
		if map_view != null:
			map_view.fx_damage(e.pos(), dot, "player_hit" if e.faction == Entity.Faction.PLAYER else "hit")
		if e.faction == Entity.Faction.PLAYER:
			last_damage_source = "les toxines"
			add_message("[color=#9fdf6a]Tu subis %d dégâts (poison/saignement/feu).[/color]" % dot)
		else:
			add_message("[color=#9fdf6a]%s subit %d (poison/saignement/feu).[/color]" % [e.display_name, dot])
	return stunned

## Tour d'un ennemi : applique les traits passifs (rage/berserk, copie, aura,
## piège) puis route vers le comportement data-driven (ai.behavior).
func _enemy_act(e: Entity) -> void:
	# Zone d'agro : un ennemi endormi ignore tout (traits passifs compris) tant
	# qu'il n'a pas été blessé, vu, ou alerté par un cri de meute proche.
	if not e.awake:
		if e.is_boss or String(e.ai.get("behavior", "")) == "stationary":
			e.awake = true
		elif e.hp < e.max_hp:
			e.awake = true                                      # a pris des dégâts
		elif dungeon.is_visible(e.x, e.y):
			e.awake = true                                      # vu (réciproque de la vision joueuse)
		elif _chebyshev(e.pos(), player.pos()) <= int(e.ai.get("aggro", 8)):
			e.awake = true
		if e.awake and String(e.ai.get("behavior", "")) != "ambush":
			for o in enemies:                                   # cri d'alerte aux voisins
				if o.is_alive() and not o.awake and String(o.ai.get("behavior", "")) != "ambush" \
						and _chebyshev(e.pos(), o.pos()) <= 4:
					o.awake = true
		else:
			return                                              # toujours endormi : tour passé
	if e.ai_cd > 0:
		e.ai_cd -= 1
	# Boss à phases (Dieu-Bête) : ajuste le comportement selon les PV.
	if e.is_boss and e.ai.get("phases", false):
		_boss_update_phase(e)
	# Rage : Gardien (boss) ET berserkers (ai.berserk), sous un seuil de PV.
	var rage_at: float = 0.8 if has_oath("glas") else 0.5
	if (e.is_boss or e.ai.get("berserk", false)) and not e.enraged and e.hp <= e.max_hp * float(e.ai.get("berserk_at", rage_at)):
		e.enraged = true
		e.atk = int(round(e.atk * float(e.ai.get("berserk_mult", 1.4))))
		if e.is_boss:
			add_message("[color=#ff4040]⚡ Le Gardien entre en RAGE ! Ses coups redoublent.[/color]")
			if map_view != null:
				map_view.fx_shake(4.0)
		else:
			add_message("[color=#ff6a40]⚡ %s entre en furie berserk ![/color]" % e.display_name)
	# Revenant : copie la puissance offensive de l'héroïne.
	if e.ai.get("copy_player", false):
		e.atk = maxi(e.atk, int(round(player.atk * float(e.ai.get("copy_ratio", 0.85)))))
	# Aura de maladie (Zombie) : contamine au contact sans consommer l'action.
	if e.ai.get("disease_aura", false) and _chebyshev(e.pos(), player.pos()) <= 1 and player.is_alive():
		apply_disease(player, 4, maxf(1.0, e.atk * 0.3))
		add_message("[color=#9fdf6a]L'aura putride de %s te contamine.[/color]" % e.display_name)
	# Pose de piège (Brigand, Kobold) : à moyenne distance, parfois, au lieu d'agir.
	var pdist: int = _chebyshev(e.pos(), player.pos())
	if e.ai.get("drops_trap", false) and e.ai_cd <= 0 and pdist >= 2 and pdist <= 6 and rng.randf() < 0.3:
		_drop_trap(e.pos())
		e.ai_cd = 5
		return
	match String(e.ai.get("behavior", "melee")):
		"charger": _enemy_act_charger(e)
		"ranged": _enemy_act_ranged(e)
		"caster": _enemy_act_caster(e)
		"fleer": _enemy_act_fleer(e)
		"teleporter": _enemy_act_teleporter(e)
		"ambush": _enemy_act_ambush(e)
		"stationary": pass            # gardiens liés : inertes, à détruire
		_: _enemy_act_melee(e)

## Intention de l'ennemi à afficher (source unique, lue par MapView pour
## télégraphier l'IA) : n'IMPLÉMENTE rien, n'inspecte que les mêmes champs
## que les comportements réels ci-dessus, dans le même ordre de priorité.
func enemy_intent(e: Entity) -> String:
	if String(e.ai.get("behavior", "")) == "ambush" and not e.revealed:
		return ""                      # ne jamais dévoiler un mimic non démasqué
	if not e.awake:
		return "sleep"
	if _manhattan(e.pos(), player.pos()) == 1:
		return "attack"
	var behavior: String = String(e.ai.get("behavior", "melee"))
	if behavior == "charger":
		var dir: Vector2i = Vector2i.ZERO
		if e.x == player.x:
			dir = Vector2i(0, signi(player.y - e.y))
		elif e.y == player.y:
			dir = Vector2i(signi(player.x - e.x), 0)
		if dir != Vector2i.ZERO:
			var p: Vector2i = e.pos()
			var steps: int = 0
			while steps < 6:
				var np: Vector2i = p + dir
				if np == player.pos():
					return "charge"
				if not dungeon.is_walkable(np.x, np.y) or enemy_at(np.x, np.y) != null:
					break
				p = np
				steps += 1
	if behavior == "ranged":
		var dist: int = _chebyshev(e.pos(), player.pos())
		if dist <= int(e.ai.get("ranged_range", 5)) and e.ai_cd <= 0 and dungeon.has_los(e.pos(), player.pos()):
			return "shoot"
	if behavior == "caster":
		var cdist: int = _chebyshev(e.pos(), player.pos())
		if e.ai_cd <= 0 and cdist <= int(e.ai.get("cast_range", 6)):
			return "summon" if String(e.ai.get("cast", "summon")) == "summon" else "cast"
	if behavior == "fleer" and e.hp <= e.max_hp * 0.4:
		return "flee"
	return "approach"

## Simule (sans toucher aux entités réelles) l'ordre des `n` prochaines
## actions — joueuse + ennemis vivants ÉVEILLÉS seulement (un ennemi endormi
## n'agit jamais). Pour la bande d'ordre des tours (Hud).
func preview_turn_order(n: int = 8) -> Array:
	var pool: Array = []
	if player != null and player.is_alive():
		pool.append({ "entity": player, "energy": float(player.energy), "speed": float(player.effective_speed()) })
	for e in enemies:
		if e.is_alive() and e.awake:
			pool.append({ "entity": e, "energy": float(e.energy), "speed": float(e.effective_speed()) })
	var order: Array = []
	while order.size() < n and not pool.is_empty():
		var best_i: int = -1
		var best_ticks: int = 999999
		for i in pool.size():
			var c: Dictionary = pool[i]
			if c["speed"] <= 0.0:
				continue
			var ticks: int = maxi(0, ceili((Entity.ACTION_COST - c["energy"]) / c["speed"]))
			if ticks < best_ticks:
				best_ticks = ticks
				best_i = i
		if best_i == -1:
			break
		for c in pool:
			c["energy"] += float(best_ticks) * c["speed"]
		pool[best_i]["energy"] -= float(Entity.ACTION_COST)
		order.append(pool[best_i]["entity"])
	return order

# --- Briques de déplacement réutilisables -------------------------------------
## Avance d'une case vers `target` (axe dominant d'abord). Renvoie true si bougé.
## Boss/élites (ai.smart_path) tentent d'abord un A* (Dungeon.next_step) pour
## contourner de grands obstacles ; repli sur la marche gloutonne si aucun
## chemin n'est trouvé (ou si la case indiquée vient d'être occupée).
func _enemy_step_toward(e: Entity, target: Vector2i) -> bool:
	if e.ai.get("smart_path", false):
		var np: Vector2i = dungeon.next_step(e.pos(), target, 400)
		if np != e.pos() and enemy_at(np.x, np.y) == null and player.pos() != np:
			e.facing = np - e.pos()
			e.x = np.x
			e.y = np.y
			return true
	var dx: int = signi(target.x - e.x)
	var dy: int = signi(target.y - e.y)
	var tries: Array
	if abs(target.x - e.x) >= abs(target.y - e.y):
		tries = [Vector2i(dx, 0), Vector2i(0, dy)]
	else:
		tries = [Vector2i(0, dy), Vector2i(dx, 0)]
	# Évitement minimal d'obstacle : si les deux tentatives directes échouent
	# (mur/arbre/rocher aligné), tente les deux directions perpendiculaires à
	# l'axe dominant, en ordre aléatoire, pour ne pas rester bloquée en ligne droite.
	var perp: Array = [Vector2i(0, 1), Vector2i(0, -1)] if tries[0].y == 0 else [Vector2i(1, 0), Vector2i(-1, 0)]
	if rng.randf() < 0.5:
		perp = [perp[1], perp[0]]
	tries.append_array(perp)
	for t in tries:
		if t == Vector2i.ZERO:
			continue
		var np: Vector2i = e.pos() + t
		if dungeon.is_walkable(np.x, np.y) and enemy_at(np.x, np.y) == null and player.pos() != np:
			e.x = np.x; e.y = np.y; e.facing = t
			return true
	return false

## S'éloigne d'une case de `from`. Renvoie true si bougé.
func _enemy_step_away(e: Entity, from: Vector2i) -> bool:
	var dx: int = signi(e.x - from.x)
	var dy: int = signi(e.y - from.y)
	for t in [Vector2i(dx, 0), Vector2i(0, dy), Vector2i(dx, dy)]:
		if t == Vector2i.ZERO:
			continue
		var np: Vector2i = e.pos() + t
		if dungeon.is_walkable(np.x, np.y) and enemy_at(np.x, np.y) == null and player.pos() != np:
			e.x = np.x; e.y = np.y; e.facing = t
			return true
	return false

func _count_allies_near(e: Entity, r: int) -> int:
	var n: int = 0
	for o in enemies:
		if o != e and o.is_alive() and _chebyshev(e.pos(), o.pos()) <= r:
			n += 1
	return n

## Attaque effective d'un ennemi (bonus de meute pour ai.pack).
func _enemy_atk(e: Entity) -> int:
	var a: int = e.atk
	if e.ai.get("pack", false):
		var allies: int = _count_allies_near(e, 2)
		a += int(round(float(e.ai.get("pack_bonus", 2)) * float(mini(allies, 3))))
	if e.has_status("weaken"):
		a -= int(round(e.status_value("weaken")))
	return maxi(1, a)

func _free_adjacent(p: Vector2i) -> Vector2i:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var np: Vector2i = p + d
		if dungeon.is_walkable(np.x, np.y) and enemy_at(np.x, np.y) == null and player.pos() != np:
			return np
	return NO_TILE

func _random_walkable_near(center: Vector2i, radius: int) -> Vector2i:
	for attempt in 16:
		var np: Vector2i = Vector2i(center.x + rng.randi_range(-radius, radius), center.y + rng.randi_range(-radius, radius))
		if np != player.pos() and dungeon.is_walkable(np.x, np.y) and enemy_at(np.x, np.y) == null:
			return np
	return NO_TILE

# --- Comportements ------------------------------------------------------------
func _enemy_act_melee(e: Entity) -> void:
	if _manhattan(e.pos(), player.pos()) == 1:
		_enemy_attack_player(e)
		return
	_enemy_step_toward(e, player.pos())

func _enemy_act_charger(e: Entity) -> void:
	if _manhattan(e.pos(), player.pos()) == 1:
		_enemy_attack_player(e)
		return
	# Aligné en ligne droite -> charge dévastatrice jusqu'au contact.
	var dir: Vector2i = Vector2i.ZERO
	if e.x == player.x:
		dir = Vector2i(0, signi(player.y - e.y))
	elif e.y == player.y:
		dir = Vector2i(signi(player.x - e.x), 0)
	if dir != Vector2i.ZERO:
		var p: Vector2i = e.pos()
		var steps: int = 0
		while steps < 6:
			var np: Vector2i = p + dir
			if np == player.pos():
				e.x = p.x; e.y = p.y; e.facing = dir
				var saved: int = e.atk
				e.atk = int(round(e.atk * 1.6))
				add_message("[color=#ff9a64]%s charge en trombe ![/color]" % e.display_name)
				_enemy_attack_player(e)
				e.atk = saved
				# L'impact projette la joueuse (1 case ; 2 pour le Bourreau).
				if player.is_alive():
					push_entity(player, dir, int(e.ai.get("push", 1)))
				return
			if not dungeon.is_walkable(np.x, np.y) or enemy_at(np.x, np.y) != null:
				break
			p = np
			steps += 1
		if steps > 0:
			e.x = p.x; e.y = p.y; e.facing = dir
			return
	_enemy_step_toward(e, player.pos())

func _enemy_act_ranged(e: Entity) -> void:
	if _manhattan(e.pos(), player.pos()) == 1:
		_enemy_attack_player(e)
		return
	var dist: int = _chebyshev(e.pos(), player.pos())
	# Pas de tir depuis le néant : l'ennemi doit être vu ET avoir la ligne de
	# vue dégagée jusqu'à la joueuse (sinon il approche/kite comme s'il n'avait
	# pas de portée disponible).
	if dist <= int(e.ai.get("ranged_range", 5)) and e.ai_cd <= 0 \
			and dungeon.is_visible(e.x, e.y) and dungeon.has_los(e.pos(), player.pos()):
		_enemy_ranged_attack(e)
		e.ai_cd = int(e.ai.get("cooldown", 1))
		return
	if dist < int(e.ai.get("kite_at", 2)) and _enemy_step_away(e, player.pos()):
		return
	_enemy_step_toward(e, player.pos())

func _enemy_ranged_attack(e: Entity) -> void:
	add_message("[color=#ffb86a]%s t'attaque à distance.[/color]" % e.display_name)
	if rng.randf() < player.dodge_chance:
		add_message("[color=#b3a8e0]Tu esquives le tir de %s ![/color]" % e.display_name)
		return
	last_damage_source = e.display_name
	var dealt: int = player.take_damage(max(1, _enemy_atk(e) - _player_def()))
	add_message("[color=#ff8a8a]%s te touche (-%d).[/color]" % [e.display_name, dealt])
	_apply_enemy_on_hit(e)
	_trigger_armor_retaliation(e, dealt)
	_check_revive()

func _enemy_act_caster(e: Entity) -> void:
	if e.ai.get("sacrifice", false) and e.hp <= e.max_hp * 0.35:
		_enemy_sacrifice(e)
		return
	var dist: int = _chebyshev(e.pos(), player.pos())
	# Invoquer ne demande pas de visibilité (des renforts qui surgissent de
	# l'obscurité, c'est correct) ; hurler/cibler la joueuse si.
	var needs_los: bool = String(e.ai.get("cast", "summon")) != "summon"
	var can_see: bool = not needs_los or (dungeon.is_visible(e.x, e.y) and dungeon.has_los(e.pos(), player.pos()))
	if e.ai_cd <= 0 and dist <= int(e.ai.get("cast_range", 6)) and can_see:
		_enemy_cast(e)
		e.ai_cd = int(e.ai.get("cooldown", 3))
		return
	if _manhattan(e.pos(), player.pos()) == 1:
		_enemy_attack_player(e)
		return
	if dist < int(e.ai.get("kite_at", 3)) and _enemy_step_away(e, player.pos()):
		return
	_enemy_step_toward(e, player.pos())

func _enemy_cast(e: Entity) -> void:
	match String(e.ai.get("cast", "summon")):
		"scream":
			add_message("[color=#d9b8ff]%s pousse un cri déchirant ![/color]" % e.display_name)
			apply_stun(player, int(e.ai.get("stun_turns", 1)))
			apply_weaken(player, int(e.ai.get("weaken_turns", 4)), float(e.ai.get("weaken_val", 3.0)))
			add_message("[color=#cdb8ff]Tu es paralysée et ta défense s'effondre ![/color]")
		_:
			_enemy_summon(e)

func _enemy_summon(e: Entity) -> void:
	if e.spawned_count >= int(e.ai.get("summon_max", 3)):
		_enemy_step_toward(e, player.pos())
		return
	var spot: Vector2i = _free_adjacent(e.pos())
	if spot == NO_TILE:
		_enemy_step_toward(e, player.pos())
		return
	var def: Dictionary = _enemy_def_by_sprite(String(e.ai.get("summon", "squelette")))
	if def.is_empty():
		return
	var m: Entity = _make_enemy(def, floor_num, spot)
	m.energy = 0
	m.awake = true
	enemies.append(m)
	e.spawned_count += 1
	add_message("[color=#c8b0ff]%s invoque un(e) %s ![/color]" % [e.display_name, m.display_name])

func _enemy_sacrifice(e: Entity) -> void:
	add_message("[color=#ff6a6a]%s se sacrifie dans une déflagration ![/color]" % e.display_name)
	ignite_area(e.pos(), int(e.ai.get("sac_radius", 2)))
	if _chebyshev(e.pos(), player.pos()) <= int(e.ai.get("sac_radius", 2)):
		var dmg: int = maxi(1, int(round(e.atk * float(e.ai.get("sac_mult", 1.6)))) - _player_def())
		last_damage_source = "le sacrifice de %s" % e.display_name
		player.take_damage(dmg)
		add_message("[color=#ff8a8a]L'explosion te frappe (-%d).[/color]" % dmg)
		apply_burn(player, 2, maxf(1.0, e.atk * 0.3))
		_check_revive()
	e.hp = 0
	on_enemy_killed(e)

func _enemy_act_fleer(e: Entity) -> void:
	var allies: int = _count_allies_near(e, 3)
	if _manhattan(e.pos(), player.pos()) == 1:
		if (e.hp <= e.max_hp * 0.5 or allies == 0) and _enemy_step_away(e, player.pos()):
			return
		_enemy_attack_player(e)
		return
	if (e.hp <= e.max_hp * 0.4 or allies == 0) and _enemy_step_away(e, player.pos()):
		return
	_enemy_step_toward(e, player.pos())

func _enemy_act_teleporter(e: Entity) -> void:
	if _manhattan(e.pos(), player.pos()) == 1:
		_enemy_attack_player(e)
		return
	if rng.randf() < float(e.ai.get("teleport_chance", 0.7)):
		var spot: Vector2i = _random_walkable_near(player.pos(), int(e.ai.get("teleport_range", 3)))
		if spot != NO_TILE:
			e.x = spot.x
			e.y = spot.y
			return
	_enemy_step_toward(e, player.pos())

func _enemy_act_ambush(e: Entity) -> void:
	if not e.revealed:
		if _chebyshev(e.pos(), player.pos()) <= 1:
			e.revealed = true
			e.sprite = "mimic"
			add_message("[color=#ff6464]Le coffre était un MIMIC ![/color]")
			var saved: int = e.atk
			e.atk = int(round(e.atk * 1.6))
			_enemy_attack_player(e)
			e.atk = saved
		return                              # reste immobile et masqué
	if _manhattan(e.pos(), player.pos()) == 1:
		_enemy_attack_player(e)
		return
	_enemy_step_toward(e, player.pos())

## Cherche une définition d'ennemi par nom de sprite (pour les invocations).
func _enemy_def_by_sprite(id: String) -> Dictionary:
	for d in Data.ENEMIES:
		if String(d.get("sprite", "")) == id:
			return d
	return {}

# --- Pièges au sol ------------------------------------------------------------
func _drop_trap(p: Vector2i) -> void:
	if p == player.pos():
		return
	for h in hazards:
		if h["pos"] == p:
			return
	hazards.append({
		"pos": p, "glyph": "^", "color": Color(0.95, 0.55, 0.45),
		"dmg": 2 + int(floor_num / 3),
		"status": { "id": "slow", "turns": 3, "value": 0.45 },
	})
	add_message("[color=#caa07a]%s dissimule un piège.[/color]" % "Un ennemi")

## Déclenche le piège éventuel sur `p` contre `victim` (la joueuse par défaut ;
## un ennemi poussé dessus le déclenche aussi — les pièges coupent dans les
## deux sens depuis la Phase 4.3).
func _trigger_hazard_at(p: Vector2i, victim: Entity = null) -> void:
	if victim == null:
		victim = player
	# Talent Pied léger (Phase 6.1) : les pièges ne se déclenchent plus sous les
	# pas de la joueuse (ils restent actifs contre les ennemis poussés dessus).
	if victim == player and player != null and player.has_talent_hook("pied_leger"):
		return
	for h in hazards.duplicate():
		if h["pos"] == p:
			hazards.erase(h)
			if victim == player:
				add_message("[color=#ff9a6a]Tu déclenches un piège ![/color]")
			else:
				add_message("[color=#ff9a6a]%s déclenche un piège ![/color]" % victim.display_name)
			var dmg: int = int(h.get("dmg", 0))
			if dmg > 0:
				if victim == player:
					last_damage_source = "un piège"
					victim.take_damage(maxi(1, dmg - _player_def()))
				else:
					victim.take_damage(maxi(1, dmg - victim.defense))
			var st: Dictionary = h.get("status", {})
			match String(st.get("id", "")):
				"slow": apply_slow(victim, int(st.get("turns", 3)), float(st.get("value", 0.4)))
				"bleed": apply_bleed(victim, int(st.get("turns", 3)), float(st.get("value", 3.0)))
				"poison": apply_poison(victim, int(st.get("turns", 3)), float(st.get("value", 3.0)))
				"weaken": apply_weaken(victim, int(st.get("turns", 3)), float(st.get("value", 3.0)))
			if victim == player:
				_check_revive()
			return

# --- Boutique -----------------------------------------------------------------
func open_shop() -> void:
	state = State.CHOICE
	current_choice = "shop"
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
	if GameState.shop_always_power() or rng.randf() < 0.5:
		var pdef: Dictionary = _pick_power_def()
		if not pdef.is_empty():
			var pitem: Dictionary = pdef.duplicate(true)
			pitem["kind"] = "power"
			pitem["price"] = 40
			shop_stock.append(pitem)
	hud.show_shop(shop_stock, run_shards)

func buy_shop_item(item: Dictionary) -> void:
	var price: int = int(item.get("price", 99999))
	if run_shards < price or not shop_stock.has(item):
		return
	run_shards -= price
	shop_stock.erase(item)
	Sfx.play("buy")
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
	Sfx.play("buy")
	player.heal(int(player.max_hp * 0.5))
	add_message("Soin à la boutique (+50% PV).")
	hud.show_shop(shop_stock, run_shards)

func leave_shop() -> void:
	_advance()

# --- Événement ----------------------------------------------------------------
func open_event() -> void:
	state = State.CHOICE
	current_choice = "event"
	current_event = Data.EVENTS[rng.randi_range(0, Data.EVENTS.size() - 1)]
	hud.show_event(current_event)

func resolve_event(choice_idx: int) -> void:
	_apply_event_effect(current_event["choices"][choice_idx])
	if not player.is_alive():
		game_over()
		return
	_advance()

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
			# Phase 5.2 : vrai pari — 55% gain, 45% perte de 15% des PV max (met
			# vraiment en jeu, indépendamment de l'étage grâce au pourcentage).
			if rng.randf() < 0.55:
				run_shards += 25
				add_message("[color=#9fff9f]Chance ! +25 Éclats.[/color]")
			else:
				last_damage_source = str(current_event.get("title", "un événement"))
				var loss: int = maxi(1, int(round(player.max_hp * 0.15)))
				player.take_damage(loss)
				add_message("[color=#ff8a8a]Piège ! −%d PV (15%%).[/color]" % loss)
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
	current_choice = "rest"
	hud.show_rest()

func rest_choice(kind: String) -> void:
	match kind:
		"heal":
			var amt: int = int(player.max_hp * 0.4)
			player.heal(amt)
			if map_view != null:
				map_view.fx_damage(player.pos(), amt, "heal")
			add_message("Repos : +%d PV." % amt)
			_advance()
		"forge":
			open_forge()
		_:
			player.base_atk += 3
			player.recompute_stats()
			add_message("Entraînement : +3 ATK (ce run).")
			_advance()

## Forge Itinérante (rest_choice "forge") : ouvre l'écran de choix de la pièce
## d'équipement à renforcer plutôt que d'en tirer une au hasard en silence.
func open_forge() -> void:
	if player.equipment.is_empty():
		add_message("La forge reste froide : aucune pièce à renforcer.")
		_advance()
		return
	state = State.CHOICE
	hud.show_forge(player.equipment)

## Renforce de ~30% les bonus de la pièce d'équipement choisie à la Forge.
func forge_choice(slot: String) -> void:
	if not player.equipment.has(slot):
		_advance()
		return
	var it: Dictionary = player.equipment[slot]
	var bonus: Dictionary = it.get("bonus", {})
	var boosted := false
	for stat in bonus.keys():
		var v = bonus[stat]
		if typeof(v) == TYPE_INT and int(v) <= 0:
			continue
		elif typeof(v) == TYPE_FLOAT and float(v) <= 0.0:
			continue
		elif typeof(v) == TYPE_INT and int(v) != 0:
			bonus[stat] = int(v) + maxi(1, int(round(abs(int(v)) * 0.3))) * signi(int(v))
			boosted = true
		elif typeof(v) == TYPE_FLOAT and float(v) != 0.0:
			bonus[stat] = float(v) * 1.3
			boosted = true
	if not boosted:
		bonus["atk"] = int(bonus.get("atk", 0)) + 2
	it["bonus"] = bonus
	player.equipment[slot] = it
	player.recompute_stats()
	add_message("[color=#ffd24a]Forge : %s renforcé ![/color]" % it.get("name", "ton équipement"))
	_advance()

## Annule le passage à la Forge et revient au choix du feu de camp.
func forge_cancel() -> void:
	open_rest()

## `abandoned` : la joueuse a quitté volontairement (pause -> Abandonner
## l'ascension) plutôt que d'être vaincue — l'étage atteint compte quand même
## pour les records, mais les Éclats banqués sont réduits (ABANDON_SHARD_MULT).
func game_over(abandoned := false) -> void:
	var stats := {
		"floor": floor_num, "level": player.level, "kills": run_kills,
		"best_hit": run_best_hit, "shards": run_shards,
		"item": str(run_best_item.get("name", "")),
		"item_color": run_best_item.get("rarity_color", Color(0.82, 0.82, 0.88)).to_html(false),
		"killed_by": "" if abandoned else last_damage_source,
		"prev_best_floor": GameState.best_floor,   # avant maj par record_run (pour "à N étage(s) du record")
		"timeline": run_timeline.duplicate(),
		"seed": run_seed,
	}
	# Serments : multiplie les Éclats banqués (réduits en plus en cas d'abandon).
	var shard_mult: float = oath_shard_mult()
	if abandoned:
		shard_mult *= ABANDON_SHARD_MULT
	var banked: int = int(round(run_shards * shard_mult))
	GameState.add_shards(banked)
	# Connaissances : récompense le progrès (étages au-delà du record) et la nouveauté
	# (Gardiens vaincus), + bonus des Serments. Calculé AVANT record_run (qui maj le record).
	var knowledge_gained: int = maxi(0, floor_num - GameState.best_floor) + run_bosses * 2 + oath_knowledge_bonus()
	if knowledge_gained > 0:
		GameState.add_knowledge(knowledge_gained)
	stats["knowledge"] = knowledge_gained
	GameState.record_run(stats)
	state = State.GAMEOVER
	var summary: String
	if abandoned:
		summary = "Tu renonces à l'Étage %d." % floor_num
	else:
		summary = "Tu es tombé à l'Étage %d (niveau %d)." % [floor_num, player.level]
	if knowledge_gained > 0:
		summary += "   ✶ +%d Connaissance(s) acquise(s)." % knowledge_gained
	hud.show_gameover(summary)

## Quitte volontairement l'ascension en cours (depuis la pause).
func abandon_run() -> void:
	game_over(true)

# --- Montée de niveau & talents -----------------------------------------------
func xp_to_next(level: int) -> int:
	# Phase 5.2 : courbe quadratique — coupe le flot de niveaux du début de run
	# (avant : 6 + level*5, quasi linéaire).
	return 10 + level * level * 3

func _check_level_up() -> void:
	while player.xp >= xp_to_next(player.level):
		player.xp -= xp_to_next(player.level)
		player.level += 1
		pending_levelups += 1
		add_message("[color=#9fff9f]★ Niveau %d ![/color]" % player.level)
		Sfx.play("levelup")
	if pending_levelups > 0 and state == State.PLAYING:
		_open_levelup()

func _open_levelup() -> void:
	state = State.LEVELUP
	hud.show_levelup(player.level)

## Tire jusqu'à 3 talents distincts (sans remise) parmi Data.TALENTS. RNG
## unifiée (Main.rng) — Hud reste sans logique, ne fait qu'afficher le choix.
func roll_talent_choices() -> Array:
	var pool: Array = Data.TALENTS.duplicate()
	var picks: Array = []
	for i in mini(3, pool.size()):
		var idx: int = rng.randi_range(0, pool.size() - 1)
		picks.append(pool[idx])
		pool.remove_at(idx)
	return picks

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
	var intent_map: Dictionary = {}
	if dungeon != null and player != null:
		for e in enemies:
			if e.is_alive() and dungeon.is_visible(e.x, e.y):
				intent_map[e.get_instance_id()] = enemy_intent(e)
	map_view.refresh(dungeon, [player] + enemies, loot, hazards, intent_map)
	hud.refresh()

func add_message(msg: String) -> void:
	messages.append(msg)
	while messages.size() > MAX_LOG:
		messages.pop_front()

## Jalon du run (récap de fin de run) : entrée de biome, Gardien vaincu, pouvoir
## ramassé... Plafonné, seuls les RUN_TIMELINE_CAP derniers jalons sont gardés.
func _push_timeline(entry: String) -> void:
	run_timeline.append(entry)
	while run_timeline.size() > RUN_TIMELINE_CAP:
		run_timeline.pop_front()

func enemy_at(x: int, y: int) -> Entity:
	for e in enemies:
		if e.is_alive() and e.x == x and e.y == y:
			return e
	return null

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return max(abs(a.x - b.x), abs(a.y - b.y))
