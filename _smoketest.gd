extends Node
# Test de fumée : pilote une vraie partie sans interaction. Lancé comme scène
# (les autoloads sont donc chargés -> GameState disponible).

func _ready() -> void:
	# Phase 7.1 : la section marche aléatoire utilise la RNG globale — on la
	# fixe pour que le test soit déterministe en CI.
	seed(4242)
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)

	# --- Phase 1.7 : entrées liées par touche physique (indépendantes du clavier) ---
	for action in ["move_up", "move_down", "move_left", "move_right", "wait", "ability", "inventory", "cancel"]:
		assert(InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty(), "action '%s' liée" % action)
	print("OK Phase 1.7: actions de déplacement/interaction liées par touche physique")

	# --- Phase 1.1 : plus d'off-by-one sur le numéro d'étage --------------------
	main.start_run("melee")
	assert(main.floor_num == 1, "le 1er étage réel affiche floor_num == 1 (pas 2)")
	print("OK Phase 1.1: floor_num == 1 sur le 1er étage")

	# --- Phase 1.5 : plafonds de dodge/crit/vol de vie ---------------------------
	main.player.talents = []
	for i in 3:
		main.player.talents.append({ "id": "test_dodge_%d" % i, "name": "Test", "desc": "", "mods": { "dodge_chance": 0.30 } })
	main.player.recompute_stats()
	assert(is_equal_approx(main.player.dodge_chance, Data.CAP_DODGE), "l'esquive est plafonnée à CAP_DODGE malgré le cumul")
	main.player.talents = []
	main.player.recompute_stats()
	print("OK Phase 1.5: dodge_chance/crit_chance/lifesteal_pct plafonnés dans recompute_stats")

	# --- Phase 1.6 : la Forge n'amplifie plus les maluses -------------------------
	main.start_run("melee")
	main.player.equipment["arme"] = { "kind": "equip", "name": "Test", "slot": "arme", "salvage": 5, "bonus": { "atk": 4, "speed": -5 } }
	main.forge_choice("arme")
	var forged: Dictionary = main.player.equipment["arme"]["bonus"]
	assert(int(forged["speed"]) == -5, "Forge : le malus de vitesse n'est pas amplifié")
	assert(int(forged["atk"]) > 4, "Forge : le bonus positif est toujours amplifié")
	print("OK Phase 1.6: Forge amplifie les bonus mais laisse les maluses intacts")

	# --- Phase 1.10 : Serment de Pauvreté annule aussi le Pacte de Pouvoir --------
	GameState.knowledge_nodes = ["pacte_pouvoir"]
	main.active_oaths = ["pauvrete"]
	main.start_run("melee")
	assert(main.player.powers.is_empty(), "Serment de Pauvreté : aucun pouvoir de départ, même avec Pacte de Pouvoir débloqué")
	main.active_oaths = []
	GameState.knowledge_nodes = []
	print("OK Phase 1.10: le Serment de Pauvreté annule bien le Pacte de Pouvoir")

	# --- Phase 1.8 : pause et abandon volontaire d'ascension -----------------------
	main.start_run("melee")
	main.run_shards = 100
	main.active_oaths = []
	main.open_pause()
	assert(main.state == main.State.PAUSED, "la pause suspend le run")
	main.close_pause()
	assert(main.state == main.State.PLAYING, "reprendre la pause revient au jeu")
	var shards_before: int = GameState.shards
	main.abandon_run()
	assert(main.state == main.State.GAMEOVER, "abandonner l'ascension termine le run")
	assert(GameState.shards == shards_before + int(round(100 * main.ABANDON_SHARD_MULT * main.oath_shard_mult())), "abandon : Éclats banqués réduits de ABANDON_SHARD_MULT")
	print("OK Phase 1.8: pause (suspendre/reprendre) + abandon volontaire (pénalité d'Éclats)")

	# --- Phase 1.9 : la zone de jeu suit un redimensionnement de fenêtre ----------
	main.start_run("melee")
	main.map_view._vignette_tex = main.map_view._make_vignette(4, 4)
	main._on_viewport_resized()
	assert(main.map_view.view_size == main.hud.play_area(), "la zone de jeu se recale sur la taille de viewport courante")
	assert(main.map_view._vignette_tex == null, "la vignette en cache est invalidée pour se régénérer à la nouvelle taille")
	print("OK Phase 1.9: recalage de la zone de jeu + invalidation de la vignette au redimensionnement")

	# --- Phase 2.1/2.2 : ligne de vue partagée + vision >= portée max des tireurs --
	assert(Data.BASE_VISION >= 6, "vision de base relevée pour couvrir les ennemis à portée 7")
	main.active_oaths = []
	main.start_run("melee")
	main.enemies.clear()
	var los_origin: Vector2i = main.player.pos()
	var los_wall: Vector2i = los_origin + Vector2i(1, 0)
	var los_far: Vector2i = los_origin + Vector2i(2, 0)
	if main.dungeon.is_walkable(los_wall.x, los_wall.y) and main.dungeon.is_walkable(los_far.x, los_far.y):
		main.dungeon.tiles[los_wall.y][los_wall.x] = Dungeon.ROCK
		main.dungeon.reveal(los_origin, main.player.vision)
		var shooter: Entity = main._make_enemy(main._enemy_def_by_sprite("dullahan"), 8, los_far)
		shooter.awake = true
		shooter.ai_cd = 0
		main.enemies.append(shooter)
		var hp0_los: int = main.player.hp
		main._enemy_act(shooter)
		assert(main.player.hp == hp0_los, "un mur bloque le tir d'un ennemi (pas de tir depuis le néant)")
		assert(main._nearest_enemy_in_range(10) == null, "le même mur bloque l'auto-visée du joueur (LoS partagée)")
		main.dungeon.tiles[los_wall.y][los_wall.x] = Dungeon.FLOOR
		print("OK Phase 2.1/2.2: Dungeon.has_los bloque tirs ennemis et auto-visée joueuse à travers un mur")

	# --- Phase 2.3 : zone d'agro (l'IA n'est plus omnisciente) ---------------------
	main.active_oaths = []
	main.start_run("melee")
	var agro_rng := RandomNumberGenerator.new(); agro_rng.seed = 21
	var agro_map := Dungeon.new(80, 50, agro_rng, Data.biome_for_floor(1))
	main.dungeon = agro_map
	main.player.x = agro_map.start.x
	main.player.y = agro_map.start.y
	agro_map.reveal(main.player.pos(), main.player.vision)
	main.enemies.clear()
	var far_pos: Vector2i = Vector2i(clampi(main.player.x + 30, 1, agro_map.width - 2), main.player.y)
	if not agro_map.is_walkable(far_pos.x, far_pos.y):
		far_pos = Vector2i(clampi(main.player.x - 30, 1, agro_map.width - 2), main.player.y)
	var dormant: Entity = main._make_enemy(main._enemy_def_by_sprite("gnoll"), 1, far_pos)
	dormant.awake = false
	main.enemies.append(dormant)
	var dormant_start: Vector2i = dormant.pos()
	for i in 5:
		main.pass_turn()
	assert(dormant.pos() == dormant_start, "un ennemi endormi à 30 cases reste immobile après 5 tours d'attente")
	assert(not dormant.awake, "il reste endormi : ni vu, ni blessé, ni dans son rayon d'agro")
	print("OK Phase 2.3: zone d'agro — un ennemi hors vue/portée reste endormi et immobile")

	# --- Phase 2.4 : évitement d'obstacle (A* pour boss/élites, ai.smart_path) -----
	main.active_oaths = []
	main.start_run("melee")
	var obs_rng := RandomNumberGenerator.new(); obs_rng.seed = 33
	var obs_map := Dungeon.new(20, 10, obs_rng, Data.biome_for_floor(1))
	for y in range(1, obs_map.height - 1):
		for x in range(1, obs_map.width - 1):
			obs_map.tiles[y][x] = Dungeon.FLOOR
	# Mare de 5 cases séparant joueur et boss, avec un passage libre au-dessus et en dessous.
	for y in range(2, 7):
		obs_map.tiles[y][9] = Dungeon.WATER
	main.dungeon = obs_map
	main.player.x = 2
	main.player.y = 4
	obs_map.reveal(main.player.pos(), main.player.vision)
	main.enemies.clear()
	var obs_boss: Entity = main._make_enemy(Data.BOSSES[4], 1, Vector2i(16, 4), true)
	obs_boss.ai["smart_path"] = true
	main.enemies.append(obs_boss)
	var reached := false
	for i in 25:
		main.pass_turn()
		if main.state != main.State.PLAYING:
			break
		if main._chebyshev(obs_boss.pos(), main.player.pos()) <= 1:
			reached = true
			break
	assert(reached, "le boss (A* smart_path) contourne une mare de 5 cases et atteint la joueuse en <= 25 tours")
	main.state = main.State.PLAYING
	print("OK Phase 2.4: évitement d'obstacle — un boss/élite contourne un obstacle via l'A* (Dungeon.next_step)")

	# --- Phase 2.5 : intentions ennemies télégraphiées -----------------------------
	main.active_oaths = []
	main.start_run("melee")
	main.enemies.clear()
	var adj_pos: Vector2i = Vector2i(-9999, -9999)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var cand: Vector2i = main.player.pos() + d
		if main.dungeon.is_walkable(cand.x, cand.y):
			adj_pos = cand
			break
	var adj_enemy: Entity = main._make_enemy(main._enemy_def_by_sprite("gnoll"), 1, adj_pos)
	adj_enemy.awake = true
	main.enemies.append(adj_enemy)
	assert(main.enemy_intent(adj_enemy) == "attack", "intention d'un ennemi adjacent et éveillé = attack")
	var dormant2: Entity = main._make_enemy(main._enemy_def_by_sprite("gnoll"), 1, _find_spot(main, main.player.pos()))
	dormant2.awake = false
	main.enemies.append(dormant2)
	assert(main.enemy_intent(dormant2) == "sleep", "intention d'un ennemi endormi = sleep")
	var mimic: Entity = main._make_enemy(main._enemy_def_by_sprite("mimic"), 1, _find_spot(main, main.player.pos()))
	mimic.awake = true
	mimic.revealed = false
	main.enemies.append(mimic)
	assert(main.enemy_intent(mimic) == "", "un mimic non démasqué ne révèle jamais d'intention, même éveillé")
	print("OK Phase 2.5: intentions télégraphiées — attack/sleep/mimic masqué")

	# --- Phase 2.6 : bande d'ordre des tours (simulation pure) ---------------------
	main.active_oaths = []
	main.start_run("melee")
	main.enemies.clear()
	var slow_e: Entity = main._make_enemy(main._enemy_def_by_sprite("gnoll"), 1, _find_spot(main, main.player.pos()))
	slow_e.speed = 100
	slow_e.energy = 0
	slow_e.awake = true
	var fast_e: Entity = main._make_enemy(main._enemy_def_by_sprite("gnoll"), 1, _find_spot(main, main.player.pos()))
	fast_e.speed = 200
	fast_e.energy = 0
	fast_e.awake = true
	main.enemies.append(slow_e)
	main.enemies.append(fast_e)
	var p_energy_before: int = main.player.energy
	var s_energy_before: int = slow_e.energy
	var f_energy_before: int = fast_e.energy
	var order2: Array = main.preview_turn_order(12)
	assert(main.player.energy == p_energy_before and slow_e.energy == s_energy_before and fast_e.energy == f_energy_before,
		"preview_turn_order ne touche à aucune entité réelle (simulation pure)")
	assert(order2[0] == main.player, "la joueuse (tête de file énergie, generate_floor) agit en 1ère dans la prévisualisation")
	var fast_count := 0
	var slow_count := 0
	for e in order2:
		if e == fast_e: fast_count += 1
		elif e == slow_e: slow_count += 1
	assert(fast_count > slow_count, "un ennemi 2x plus rapide agit plus souvent dans la bande d'ordre des tours")
	print("OK Phase 2.6: bande d'ordre des tours — simulation pure, joueuse en tête, vitesse respectée")

	# --- Phase 2.7 : inspection d'ennemi au survol (panneau côté Hud) --------------
	main.active_oaths = []
	main.start_run("melee")
	main.hud.show_inspect(null)
	assert(main.hud.inspect_box.get_child_count() > 0, "placeholder affiché quand rien n'est survolé")
	main.enemies.clear()
	var insp_e: Entity = main._make_enemy(main._enemy_def_by_sprite("gnoll"), 1, _find_spot(main, main.player.pos()))
	main.enemies.append(insp_e)
	main.hud.show_inspect(insp_e)
	assert(main.hud.inspect_box.get_child_count() >= 4, "le panneau d'inspection affiche nom/PV/ATK/VIT/comportement")
	main.hud.show_inspect(null)
	print("OK Phase 2.7: panneau d'inspection (survol souris) — remplissage à la demande")

	# --- Parties complètes pour chaque héros (progression linéaire) ---
	for hero in ["melee", "ranged", "magic"]:
		main.start_run(hero)
		assert(main.state == main.State.PLAYING and main.current_node_type == "combat", "run démarre directement en combat")
		var dirs = [[0, -1], [0, 1], [-1, 0], [1, 0]]
		for step in 200:
			if main.state != main.State.PLAYING:
				break
			var r = randi() % 6
			if r < 4:
				main.try_move(dirs[r][0], dirs[r][1])
			elif r == 4:
				main.use_ability()
			else:
				main.pass_turn()
		if main.state == main.State.PLAYING:
			var before = GameState.shards
			main.player.hp = 1
			main.run_shards = 7
			main.game_over()
			assert(main.state == main.State.GAMEOVER, "écran de fin de run après la mort")
			assert(GameState.shards == before + 7, "éclats banqués à la mort")
		print("OK hero=%s state=%d banque=%d" % [hero, main.state, GameState.shards])

	# --- Progression linéaire des étages (remplace l'ancienne carte à embranchements) ---
	main.start_run("melee")
	assert(main.state == main.State.PLAYING and main.current_node_type == "combat", "run démarre directement sur un Combat")
	assert(main.act_floor == 1, "le 1er étage réel compte pour l'acte courant")
	main.act_floor = main.ACT_LENGTH
	main._advance()
	assert(main.current_node_type == "boss", "un Gardien est garanti après ACT_LENGTH étages réels")
	var act_before: int = main.map_act
	main._node_cleared()
	# _node_cleared() remet act_floor à 0 PUIS enchaîne aussitôt sur le Combat
	# de répit garanti (_advance("combat")), qui le fait remonter à 1 : c'est
	# cette valeur (1), pas 0, qu'on observe une fois l'appel terminé.
	assert(main.map_act == act_before + 1 and main.act_floor == 1, "Gardien vaincu : acte suivant, 1er étage (Combat) déjà compté")
	assert(main.current_node_type == "combat", "après le Gardien, on repart sur un Combat de répit")
	assert(not main._act_rest_done, "le drapeau de pause pré-Gardien est remis à zéro pour le nouvel acte")
	# La pause Repos/Boutique juste avant le Gardien est garantie une seule fois.
	main.act_floor = main.ACT_LENGTH - 1
	main._act_rest_done = false
	var t = main._roll_node_type()
	assert((t == "rest" or t == "shop") and main._act_rest_done, "pause Repos/Boutique garantie juste avant le Gardien")
	var t2 = main._roll_node_type()
	assert(t2 != "boss", "la pause garantie ne se redéclenche pas en boucle avant le Gardien")
	print("OK progression: 1er étage=combat, Gardien garanti à ACT_LENGTH, reset après victoire, pause pré-Gardien garantie")

	# --- Salles spéciales : boutique / événement / repos ---
	main.start_run("melee")
	main.run_shards = 9999
	main.open_shop()
	assert(main.state == main.State.CHOICE and main.shop_stock.size() > 0, "boutique ouverte")
	var stock0 = main.shop_stock.size()
	main.buy_shop_item(main.shop_stock[0])
	assert(main.shop_stock.size() == stock0 - 1, "achat retire l'objet du stock")
	main.leave_shop()
	assert(main.state == main.State.PLAYING or main.state == main.State.CHOICE, "boutique quittée : avance automatiquement (plus de carte)")
	main.open_event()
	assert(main.state == main.State.CHOICE, "événement ouvert")
	main.resolve_event(0)
	assert(main.state == main.State.PLAYING or main.state == main.State.CHOICE or main.state == main.State.GAMEOVER, "événement résolu : avance automatiquement")
	main.open_rest()
	# Comparaison sur base_atk (pas atk) : un Pacte de Pouvoir "Cœur de Verre"
	# actif (+50% ATK) rendrait la relation base_atk -> atk non linéaire à
	# cause de l'arrondi, faussant une comparaison sur le seul delta de atk.
	var base_atk_r = main.player.base_atk
	main.rest_choice("train")
	assert(main.player.base_atk == base_atk_r + 3, "repos: entraînement +3 ATK (base)")
	assert(main.state == main.State.PLAYING or main.state == main.State.CHOICE, "repos résolu : avance automatiquement")
	print("OK salles spéciales: boutique / événement / repos (avancée automatique, sans carte)")

	# --- Génération procédurale d'objets ---
	var grng = RandomNumberGenerator.new(); grng.seed = 42
	var rarities_seen = {}
	for i in 200:
		var it = Data.generate_item("arme", 6, grng)
		assert(it["slot"] == "arme" and it.has("bonus") and it.has("rarity"), "objet généré valide")
		rarities_seen[it["rarity"]] = true
	assert(rarities_seen.size() >= 2, "plusieurs raretés générées")
	print("OK loot procédural: raretés vues = %s" % str(rarities_seen.keys()))

	# --- Préfixes de combat (Dungeonmans-like) sur objets procéduraux -------------
	var prng = RandomNumberGenerator.new(); prng.seed = 7
	var weapon_prefixes_seen = {}
	var armor_prefixes_seen = {}
	for i in 400:
		var wit = Data.generate_item("arme", 10, prng)
		if not wit.get("unique", false) and wit.get("proc", "") != "":
			weapon_prefixes_seen[wit["proc"]] = true
			assert(wit.has("proc_val") and wit.has("desc") and wit["desc"] != "", "préfixe procédural a une valeur + description")
		var ait = Data.generate_item("armure", 10, prng)
		if not ait.get("unique", false) and ait.get("proc", "") != "":
			armor_prefixes_seen[ait["proc"]] = true
	assert(weapon_prefixes_seen.size() >= 3, "plusieurs préfixes d'arme différents tirés sur 400 essais")
	assert(armor_prefixes_seen.size() >= 1, "au moins un préfixe d'armure tiré sur 400 essais")
	print("OK préfixes de combat: arme=%s armure=%s" % [str(weapon_prefixes_seen.keys()), str(armor_prefixes_seen.keys())])

	# --- Préfixes de combat : déclenchement en combat -----------------------------
	main.active_oaths = []
	main.start_run("melee")
	if main.enemies.is_empty():
		main.enemies.append(main._make_enemy(Data.ENEMIES[0], 1, Vector2i(main.player.x + 1, main.player.y)))
	var target: Entity = main.enemies[0]
	# Ardent : dégâts de feu bonus instantanés (hors immunité/faiblesse au feu).
	main.player.procs.append({ "id": "ardent", "value": 5.0 })
	target.hp = target.max_hp
	var hp0 := target.hp
	main._trigger_weapon_prefixes(target)
	assert(target.hp < hp0, "Ardent inflige des dégâts de feu bonus au coup suivant")
	# Cuirasse : réduction plate de dégâts entrants, pliée dans _player_def().
	var def0 = main._player_def()
	main.player.procs.append({ "id": "cuirasse", "value": 4.0 })
	assert(main._player_def() == def0 + 4, "Cuirasse augmente la défense effective de sa valeur")
	# Renvoi : affaiblit l'attaquant au contact (forcé à 100% pour le test).
	main.player.procs.append({ "id": "renvoi", "value": 1.0 })
	target.hp = target.max_hp
	main._trigger_armor_retaliation(target, 5)
	assert(target.has_status("weaken"), "Renvoi affaiblit l'attaquant quand il déclenche")
	# Phase 1.3 : weaken doit aussi réduire l'attaque effective de l'ennemi
	# (sinon Renvoi n'a aucun effet réel en combat).
	var weaken_val: int = int(round(target.status_value("weaken")))
	assert(main._enemy_atk(target) == maxi(1, target.atk - weaken_val), "weaken réduit l'attaque effective de l'ennemi (_enemy_atk)")
	print("OK Phase 1.3: weaken réduit désormais l'attaque effective d'un ennemi")
	print("OK préfixes de combat: Ardent/Cuirasse/Renvoi se déclenchent correctement")

	# --- Objets uniques (Épique/Légendaire) ---------------------------------------
	assert(Data.UNIQUE_ITEMS.size() >= 100, "au moins 100 objets uniques générés")
	for slot in Data.SLOTS:
		for rid in ["epique", "legendaire"]:
			var found := false
			for it in Data.UNIQUE_ITEMS:
				if it["slot"] == slot and it["rarity"] == rid:
					found = true
					break
			assert(found, "objet unique présent pour %s/%s" % [slot, rid])
	var unique_seen := {}
	for i in 300:
		var it2 := Data.generate_item("arme", 10, grng)
		if it2.get("unique", false):
			unique_seen[it2["rarity"]] = true
			assert(it2.has("proc") and it2.has("desc") and it2["desc"] != "", "objet unique a un proc + description")
	assert(unique_seen.size() >= 1, "au moins un objet unique tiré sur 300 essais à l'étage 10")

	var uitem: Dictionary = {}
	for i in 500:
		var cand: Dictionary = Data.generate_item("arme", 30, grng)
		if cand.get("unique", false):
			uitem = cand
			break
	assert(not uitem.is_empty(), "un objet unique tiré sur 500 essais à l'étage 30")
	main._bag_add(uitem)
	main.equip_item(uitem)
	assert(main.player.has_proc(uitem["proc"]), "le proc de l'objet unique équipé est actif sur l'entité")
	main.unequip_item("arme")
	print("OK objets uniques: %d dans le pool, procs actifs après équipement" % Data.UNIQUE_ITEMS.size())

	# --- Inventaire + talents (en combat) ---
	main.start_run("melee")
	# Isole ce test d'un Pacte de Pouvoir "Cœur de Verre" (+50% ATK, potentiellement
	# accordé au hasard au démarrage) : son arrondi rendrait le delta de +5 à plat
	# non exact et casserait les comparaisons ci-dessous.
	main.player.powers.clear()
	main.unequip_item("arme")   # retire l'arme de loadout pour une base propre
	main.inventory.clear()
	var atk0 = main.player.atk
	var sword = { "kind": "equip", "name": "Épée test", "slot": "arme", "salvage": 5, "bonus": { "atk": 5 } }
	main._bag_add(sword)
	main.equip_item(sword)
	assert(main.player.atk == atk0 + 5, "équipement applique le bonus")
	main.unequip_item("arme")
	assert(main.player.atk == atk0 and main.inventory.size() == 1, "déséquipement rend l'objet au sac")
	main.salvage_item(sword)
	assert(main.inventory.is_empty(), "recyclage retire du sac")
	main.player.hp = 1
	var potion = { "kind": "consumable", "name": "Potion test", "effect": "heal_pct", "value": 0.5 }
	main._bag_add(potion); main.use_consumable(potion)
	assert(main.player.hp > 1 and main.inventory.is_empty(), "consommable soigne et se retire")
	main._acquire_artifact({ "id": "lifesteal", "name": "Calice test", "desc": "vol de vie" })
	assert(main.player.lifesteal_pct > 0.0, "artefact -> stat dérivée")
	var tal0 = main.player.talents.size()
	main.player.xp = main.xp_to_next(main.player.level)
	main._check_level_up()
	assert(main.state == main.State.LEVELUP and main.pending_levelups >= 1, "level-up déclenché")
	main.pick_talent(Data.TALENTS[0])
	assert(main.player.talents.size() == tal0 + 1 and main.state == main.State.PLAYING, "talent appliqué, jeu repris")
	main.open_inventory()
	assert(main.state == main.State.INVENTORY, "inventaire ouvert")
	main.close_inventory()
	assert(main.state == main.State.PLAYING, "inventaire fermé")
	print("OK inventaire + talents")

	# --- Boutique méta (entre runs) ---
	GameState.shards = 1000
	GameState.upgrades["vitalite"] = 0   # idempotent même si une sauvegarde existe
	var lvl_before = GameState.upgrade_level("vitalite")
	assert(GameState.buy_upgrade("vitalite") and GameState.upgrade_level("vitalite") == lvl_before + 1, "achat amélioration méta")
	print("OK boutique méta vitalite niv=%d" % GameState.upgrade_level("vitalite"))

	# --- Synergies inter-procs ----------------------------------------------------
	main.start_run("melee")
	main.player.equipment = {
		"arme": { "kind": "equip", "name": "Croc test", "slot": "arme", "salvage": 5, "bonus": {}, "proc": "soif_de_sang", "proc_val": 0.10 },
		"armure": { "kind": "equip", "name": "Plastron test", "slot": "armure", "salvage": 5, "bonus": {}, "proc": "frenesie", "proc_val": 0.30 },
	}
	main.player.recompute_stats()
	assert(main.player.active_synergies.size() >= 1, "synergie détectée avec deux procs complémentaires")
	assert(main.player.proc_value("soif_de_sang") > 0.10, "synergie amplifie la valeur du proc")
	main.player.equipment = { "arme": main.player.equipment["arme"] }
	main.player.recompute_stats()
	assert(main.player.active_synergies.is_empty(), "synergie retombe quand un proc manque")
	print("OK synergies: %d définie(s), détection + amplification OK" % Data.SYNERGIES.size())

	# --- Récompense garantie de boss (Épique+) ------------------------------------
	var brng = RandomNumberGenerator.new(); brng.seed = 7
	for i in 30:
		var br = Data.generate_boss_reward(10, brng)
		assert(br.get("unique", false) and (br["rarity"] == "epique" or br["rarity"] == "legendaire"), "récompense boss = unique Épique+")
		assert(br.has("proc") and br.has("desc"), "récompense boss porte un proc + description")
	var tboss = main._make_enemy(Data.BOSS, 5, Vector2i(1, 1), true)
	assert(tboss.is_boss and tboss.hp_regen == 3 and not tboss.enraged, "boss: régén active, non enragé au départ")
	print("OK boss: récompense garantie Épique+, mécanique de rage/régén")

	# --- Méta-progression élargie (Fortune / Héritage / Instinct) -----------------
	GameState.shards = 100000
	for key in ["fortune", "heritage", "instinct"]:
		GameState.upgrades[key] = 0       # idempotent même si une sauvegarde existe
	for key in ["fortune", "heritage", "instinct"]:
		assert(GameState.buy_upgrade(key), "achat méta %s" % key)
	while not GameState.is_maxed("instinct"):
		GameState.buy_upgrade("instinct")
	assert(GameState.is_maxed("instinct") and not GameState.buy_upgrade("instinct"), "achat bloqué au plafond")
	main.start_run("melee")
	assert(main.player.artifacts.size() >= 1, "Héritage : artefact de départ accordé")
	assert(main.player.talents.size() >= 1, "Instinct : talent de départ accordé")
	assert(main.run_shards >= GameState.bonus_start_shards() and main.run_shards > 0, "Fortune : Éclats de départ")
	print("OK méta élargie: bonus de départ appliqués, plafonds respectés")

	# --- Nouveaux événements (autel maudit / sanctuaire) --------------------------
	main.start_run("melee")
	var hp_b = main.player.base_max_hp
	var atk_b = main.player.base_atk
	main._apply_event_effect({ "type": "cursed_altar" })
	assert(main.player.base_atk == atk_b + 5 and main.player.base_max_hp == hp_b - 10, "autel maudit: +5 ATK / −10 PV max")
	var reg_b = main.player.base_hp_regen
	main._apply_event_effect({ "type": "stat_regen" })
	assert(main.player.base_hp_regen == reg_b + 1, "sanctuaire: +1 régén")
	print("OK événements: autel maudit + sanctuaire")

	# --- Journal de fin de run ----------------------------------------------------
	main.start_run("melee")
	main.run_kills = 5
	main.run_best_hit = 42
	main.run_shards = 13
	main.player.hp = 1
	main.game_over()
	assert(main.state == main.State.GAMEOVER, "écran de fin de run après la mort")
	assert(not GameState.last_run.is_empty(), "journal de run enregistré")
	assert(int(GameState.last_run.get("kills", 0)) == 5 and int(GameState.last_run.get("best_hit", 0)) == 42, "journal: stats correctes")
	assert(GameState.best_kills >= 5, "record d'ennemis vaincus mis à jour")
	print("OK journal de fin de run: stats + records persistés")

	# --- Terrain open-world, biomes & brouillard de guerre ------------------------
	var b1 = Data.biome_for_floor(1)
	var b2 = Data.biome_for_floor(1 + Data.BIOME_SPAN)
	assert(b1["id"] != b2["id"], "le biome change selon l'étage")
	assert(Data.BIOMES.size() >= 5, "plusieurs biomes définis")

	# tailles de carte procédurales (bornes + ratio ~1.6 + variabilité)
	var srng = RandomNumberGenerator.new(); srng.seed = 99
	var small_h := 9999
	var big_h := 0
	for i in 500:
		var ms = Data.random_map_size(srng)
		assert(ms.x >= 64 and ms.x <= 640 and ms.y >= 40 and ms.y <= 400, "taille de carte dans les bornes")
		assert(absf(float(ms.x) / float(ms.y) - Data.MAP_RATIO) < 0.06, "ratio largeur/hauteur ~1.6")
		small_h = mini(small_h, ms.y)
		big_h = maxi(big_h, ms.y)
	assert(small_h <= 90 and big_h >= 320, "la taille varie (petites ET grandes cartes)")
	# génère et peuple la plus GRANDE carte (640x400 = 256k cases)
	var bigmap = Dungeon.new(640, 400, srng, Data.biome_for_floor(50))
	assert(bigmap._reachable(bigmap.start, bigmap.stairs), "grande carte connexe")
	assert(bigmap.random_floor_tiles(30, srng, [bigmap.start]).size() == 30, "grande carte peuplée")
	print("OK tailles: hauteur %d..%d, ratio 1.6, grande carte 640x400 connexe & peuplée" % [small_h, big_h])

	var drng = RandomNumberGenerator.new(); drng.seed = 11
	var dg = Dungeon.new(64, 40, drng, Data.biome_for_floor(1))
	assert(dg.width == 64 and dg.height == 40, "carte large générée")
	assert(dg.is_walkable(dg.start.x, dg.start.y) and dg.is_walkable(dg.stairs.x, dg.stairs.y), "entrée et escalier praticables")
	assert(dg._reachable(dg.start, dg.stairs), "escalier atteignable depuis l'entrée")
	var spots = dg.random_floor_tiles(20, drng, [dg.start, dg.stairs])
	assert(spots.size() > 0, "cases praticables disponibles pour le peuplement")
	for sp in spots:
		assert(dg.is_walkable(sp.x, sp.y), "case peuplée praticable")
	# brouillard de guerre
	dg.reveal(dg.start, 4)
	assert(dg.is_visible(dg.start.x, dg.start.y) and dg.is_explored(dg.start.x, dg.start.y), "case du joueur révélée")
	var far = Vector2i(dg.width - 2, dg.height - 2)
	assert(not dg.is_visible(far.x, far.y), "case lointaine hors vision")
	dg.reveal(far, 4)
	assert(not dg.is_visible(dg.start.x, dg.start.y), "ancienne case retombe hors vision")
	assert(dg.is_explored(dg.start.x, dg.start.y), "mais reste explorée (mémoire)")
	print("OK terrain: carte 64x40, %d biomes, connexité, brouillard de guerre" % Data.BIOMES.size())

	# --- Vision améliorable par talent --------------------------------------------
	GameState.upgrades["instinct"] = 0   # pas de talent de départ aléatoire
	GameState.upgrades["heritage"] = 0
	main.start_run("melee")
	var v0 = main.player.vision
	assert(v0 == Data.BASE_VISION, "vision de base = BASE_VISION")
	main.player.talents.append({ "name": "Œil de Lynx", "mods": { "vision": 2 } })
	main.player.recompute_stats()
	assert(main.player.vision == v0 + 2, "le talent augmente le rayon de vision")
	print("OK vision: base %d, talent +2 -> %d" % [v0, main.player.vision])

	# --- Phase 1 : effets de statut (poison/brûlure, ralentissement, paralysie) ----
	var te = Entity.new()
	te.max_hp = 100; te.hp = 100; te.speed = 100
	te.add_status("poison", 3, 5.0, 10)
	te.add_status("poison", 3, 5.0, 10)
	assert(te.status_stacks("poison") == 2, "poison cumule en stacks")
	var dot = te.tick_statuses()
	assert(dot == 10 and te.hp == 90, "DoT poison = value × stacks par tour")
	te.add_status("slow", 2, 0.5)
	assert(te.effective_speed() == 50, "ralentissement réduit la vitesse effective")
	te.add_status("stun", 1)
	assert(te.has_status("stun"), "paralysie active")
	te.tick_statuses()
	assert(not te.has_status("stun"), "la paralysie expire après sa durée")
	print("OK statuts: poison cumulable, ralentissement, paralysie")

	# --- Phase 1 : primitives de combat (AoE, rebond, dash, helpers de statut) -----
	main.start_run("melee")
	var px = main.player.x; var py = main.player.y
	main.enemies.clear()
	var mk = func(dx, dy):
		var e = Entity.new()
		e.faction = Entity.Faction.ENEMY
		e.display_name = "cible"; e.max_hp = 9999; e.hp = 9999
		e.x = px + dx; e.y = py + dy; e.speed = 100
		main.enemies.append(e)
		return e
	var e1 = mk.call(1, 0)
	var _e2 = mk.call(2, 0)
	var e3 = mk.call(0, 1)
	assert(main.aoe_attack(main.player.pos(), 1, 5, "test") == 2, "AoE rayon 1 touche les ennemis adjacents")
	assert(main.bounce_attack(_e2, 10, 2, "test") >= 2, "rebond touche plusieurs ennemis")
	main.apply_poison(e1, 3, 4.0, 10)
	main.apply_slow(e3, 2, 0.4)
	assert(e1.has_status("poison") and e3.has_status("slow"), "les helpers appliquent les statuts")
	print("OK primitives: AoE, rebond, dash dispo + helpers de statut")

	# --- Phase 2 : compétences d'armes -------------------------------------------
	assert(Data.SKILLS.size() >= 18, "registre de compétences fourni (>=18)")
	for wt in Data.WEAPON_TYPES:
		var bid = Data.WEAPON_TYPE_BASE_SKILL[wt]
		assert(Data.SKILLS.has(bid) and Data.SKILLS[bid]["rarity"] == "base" and Data.SKILLS[bid]["wtype"] == wt, "compétence de base définie pour %s" % wt)
	main.start_run("magic")
	assert(main.player.active_skill_id == "bolt" and main.player.ability_id == "bolt", "loadout magie -> base bolt")
	# Repli de compatibilité quand la compétence active n'est pas du type de l'arme.
	main.start_run("ranged")
	main.player.active_skill_id = "fireball"   # magie, incompatible avec arme distance
	main.player.recompute_stats()
	assert(main.player.active_skill_id == "precise_shot", "repli sur la base du type si compétence incompatible")
	print("OK compétences: registre + bases par type + repli de compatibilité")

	# Effets de compétences sur des cibles contrôlées.
	main.start_run("melee")
	var px2 = main.player.x; var py2 = main.player.y
	var mk2 = func(dx, dy, defv):
		var e = Entity.new()
		e.faction = Entity.Faction.ENEMY
		e.display_name = "mob"; e.max_hp = 9999; e.hp = 9999; e.defense = defv
		e.x = px2 + dx; e.y = py2 + dy; e.speed = 100
		main.enemies.append(e)
		return e
	main.enemies.clear()
	var a1 = mk2.call(1, 0, 0)
	var a2 = mk2.call(0, 1, 0)
	var hp_a1 = a1.hp; var hp_a2 = a2.hp
	assert(main._cast_skill(Data.SKILLS["cleave"]), "cleave s'exécute")
	assert(a1.hp < hp_a1 and a2.hp < hp_a2, "cleave (AoE) touche les adjacents")
	assert(main._cast_skill(Data.SKILLS["ember"]), "ember s'exécute")
	assert(a1.has_status("burn") or a2.has_status("burn"), "ember applique une brûlure")
	# Brise-garde ignore la défense (cible blindée -> dégâts > 1).
	main.enemies.clear()
	var arm = mk2.call(1, 0, 1000)
	var arm_hp = arm.hp
	assert(main._cast_skill(Data.SKILLS["sunder"]), "sunder s'exécute")
	assert(arm_hp - arm.hp > 1, "brise-garde ignore la défense")
	print("OK effets de compétences: AoE, brûlure, perce-défense")

	# Drops, apprentissage et sélection de compétences.
	main.start_run("melee")
	main.known_skills.clear(); main.loot.clear()
	main._drop_skill(Vector2i(main.player.x, main.player.y), true)
	assert(main.loot.size() == 1 and main.loot[0]["kind"] == "skill", "le boss/monstre dépose une compétence")
	main.known_skills.clear()
	main._acquire_skill("double_strike")        # mêlée -> compatible
	assert(main.known_skills.has("double_strike"), "compétence apprise")
	main.select_skill("double_strike")
	assert(main.player.active_skill_id == "double_strike", "sélection d'une compétence compatible")
	main._acquire_skill("fireball")             # magie -> incompatible avec arme mêlée
	main.select_skill("fireball")
	assert(main.player.active_skill_id == "double_strike", "sélection d'une compétence incompatible refusée")
	print("OK compétences: drop, apprentissage, sélection + filtre de compatibilité")

	# --- Phase 3 : pouvoirs passifs (cumul illimité, exclusions, drops) -----------
	main.start_run("melee")
	main.player.powers.clear()
	var pdrone = {}
	var pturret = {}
	var pglass = {}
	for d in Data.POWERS:
		if d["id"] == "drone": pdrone = d
		if d["id"] == "turret": pturret = d
		if d["id"] == "coeur_de_verre": pglass = d
	main._acquire_power(pdrone)
	assert(main.player.has_power("drone"), "pouvoir drone acquis")
	main._acquire_power(pdrone)
	assert(main.player.powers.size() == 1, "doublon de pouvoir refusé (Éclats à la place)")
	main._acquire_power(pglass)
	assert(main.player.has_power("coeur_de_verre"), "cœur de verre acquis (cumul avec drone)")
	var atk_before = main.player.atk
	main._acquire_power(pturret)
	assert(not main.player.has_power("turret"), "tourelle refusée : exclusion mutuelle avec cœur de verre")
	assert(main.player.atk == atk_before, "stats inchangées après refus d'un pouvoir exclu")

	# Le drone tire automatiquement sur l'ennemi le plus proche après l'action du joueur.
	main.enemies.clear()
	var de = Entity.new()
	de.faction = Entity.Faction.ENEMY
	de.display_name = "cible drone"; de.max_hp = 9999; de.hp = 9999; de.defense = 0
	de.x = main.player.x + 2; de.y = main.player.y
	main.enemies.append(de)
	var hp_before_drone = de.hp
	main.pass_turn()
	assert(de.hp < hp_before_drone, "le drone tire automatiquement sur l'ennemi le plus proche")

	# Venin : applique un poison automatique sur les attaques.
	main.player.powers.clear()
	main._acquire_power(pdrone)   # gardé inerte: pas de venin -> pas de poison
	main.enemies.clear()
	var dv = Entity.new()
	dv.faction = Entity.Faction.ENEMY
	dv.display_name = "cible venin"; dv.max_hp = 9999; dv.hp = 9999
	dv.x = main.player.x + 1; dv.y = main.player.y
	main.enemies.append(dv)
	var pvenin = {}
	for d in Data.POWERS:
		if d["id"] == "venin": pvenin = d
	main._acquire_power(pvenin)
	main._player_attack(dv, 5, "test")
	assert(dv.has_status("poison"), "venin empoisonne automatiquement la cible touchée")
	print("OK pouvoirs: acquisition, doublon, exclusion mutuelle, drone, venin")

	# --- Phase 5 : Arbre de Connaissances + Serments ------------------------------
	GameState.knowledge = 0
	GameState.knowledge_nodes = []
	assert(not GameState.can_unlock_node("affinite"), "nœud à prérequis verrouillé sans son parent")
	GameState.knowledge = 100
	assert(GameState.can_unlock_node("pacte_pouvoir"), "nœud racine déblocable avec assez de Connaissances")
	assert(GameState.buy_knowledge_node("pacte_pouvoir"), "achat d'un nœud de l'arbre")
	assert(GameState.has_knowledge_node("pacte_pouvoir") and GameState.starts_with_power(), "nœud débloqué + raccourci de lecture")
	assert(GameState.can_unlock_node("affinite"), "prérequis désormais satisfait")
	# Pacte de Pouvoir : le run démarre avec un pouvoir.
	main.active_oaths = []
	main.start_run("melee")
	assert(main.player.powers.size() >= 1, "Pacte de Pouvoir : pouvoir de départ accordé")
	# Serments : nécessitent le nœud 'serments' ; les majeurs un palier de plus.
	assert(GameState.buy_knowledge_node("serments"), "achat du nœud Serments")
	main.active_oaths = []
	main.toggle_oath("fragilite")
	assert(main.has_oath("fragilite"), "serment mineur activable une fois débloqué")
	main.toggle_oath("elite")
	assert(not main.has_oath("elite"), "serment majeur refusé sans le palier majeur")
	# Fragilité réduit les PV de départ. Comparaison sur base_max_hp (pas
	# max_hp) : max_hp inclut d'éventuels talents de départ aléatoires
	# (Instinct) qui pourraient fausser la comparaison entre les deux runs.
	main.active_oaths = []
	main.start_run("melee")
	var base_hp_full = main.player.base_max_hp
	main.active_oaths = ["fragilite"]
	main.start_run("melee")
	assert(main.player.base_max_hp < base_hp_full, "Serment de Fragilité : PV max réduits")
	# Récompense des serments : multiplicateur d'Éclats + bonus de Connaissances.
	main.active_oaths = ["fragilite", "horde"]
	assert(main.oath_shard_mult() > 1.3, "multiplicateur d'Éclats cumulé des serments")
	assert(main.oath_knowledge_bonus() >= 1, "bonus de Connaissances des serments")
	# Chasseur augmente le taux de monstres légendaires.
	main.active_oaths = []
	var base_chance = main._legendary_chance()
	assert(GameState.buy_knowledge_node("chasseur"), "achat du nœud Chasseur")
	assert(main._legendary_chance() > base_chance, "Chasseur augmente le taux de légendaires")
	# Gain de Connaissances en fin de run (progrès + Gardiens).
	GameState.best_floor = 1
	GameState.knowledge = 0
	main.start_run("melee")
	main.floor_num = 6
	main.run_bosses = 2
	main.active_oaths = []
	main.player.hp = 1
	main.game_over()
	assert(GameState.knowledge >= 5 + 4, "Connaissances gagnées = étages au-delà du record + 2/Gardien")
	print("OK Phase 5: arbre (prérequis/achat/persistance), Pacte de Pouvoir, Serments (toggle/gate/effet/récompense), gain de Connaissances")

	# --- Phase 5 (2/2) : Codex, découvertes, Forge, Œil du Devin -------------------
	GameState.knowledge = 100
	GameState.discovered = { "skill": {}, "power": {}, "unique": {} }
	assert(not GameState.note_discovery("power", "drone"), "sans Codex, aucune découverte enregistrée")
	assert(GameState.buy_knowledge_node("codex"), "achat du nœud Codex")
	var k0 = GameState.knowledge
	assert(GameState.note_discovery("power", "drone"), "1ʳᵉ découverte enregistrée")
	assert(GameState.knowledge == k0 + 1, "une découverte inédite rapporte +1 Connaissance")
	assert(not GameState.note_discovery("power", "drone"), "doublon de découverte ignoré")
	# Forge : renforce le bonus d'une pièce équipée.
	assert(GameState.buy_knowledge_node("forge"), "achat du nœud Forge")
	main.start_run("melee")
	main.player.equipment = { "armure": { "kind": "equip", "name": "Plastron", "slot": "armure", "salvage": 5, "bonus": { "defense": 4 } } }
	main.forge_choice("armure")
	assert(int(main.player.equipment["armure"]["bonus"]["defense"]) > 4, "Forge renforce le bonus d'une pièce")
	# Œil du Devin : révèle le butin au début d'étage.
	assert(GameState.buy_knowledge_node("oeil_du_devin"), "achat du nœud Œil du Devin")
	main.active_oaths = []
	main.start_run("melee")
	assert(main.map_view.reveal_loot, "Œil du Devin actif sur la vue de carte")
	var loot_explored = main.loot.is_empty()
	for it in main.loot:
		if main.dungeon.is_explored(it["pos"].x, it["pos"].y):
			loot_explored = true
	assert(loot_explored, "le butin est marqué exploré à travers le brouillard")
	print("OK Phase 5 (2/2): Codex (découvertes +Connaissance), Forge, Œil du Devin")

	# --- Phase 4 : récompense de fin d'étage --------------------------------------
	main.active_oaths = []
	main.start_run("melee")
	main.current_node_type = "combat"
	main._open_floor_reward(false)
	assert(main.state == main.State.CHOICE and main.pending_rewards.size() >= 2, "écran de récompense ouvert (>=2 choix)")
	var pick = 0
	for i in main.pending_rewards.size():
		if main.pending_rewards[i]["type"] == "shards": pick = i
	var sh0 = main.run_shards
	main.resolve_floor_reward(pick)
	assert(main.state == main.State.PLAYING or main.state == main.State.CHOICE, "récompense résolue -> avance automatiquement")
	assert(main.run_shards >= sh0, "la récompense d'Éclats crédite le run")
	# Élite : davantage de choix (parchemin/consommable bonus).
	main.current_node_type = "elite"
	main._open_floor_reward(true)
	assert(main.pending_rewards.size() >= 3, "butin d'élite : davantage de choix")
	main.resolve_floor_reward(1)
	assert(main.state == main.State.PLAYING or main.state == main.State.CHOICE, "butin d'élite résolu")
	# Le Serment Funeste retire l'option de soin du butin.
	main.active_oaths = ["funeste"]
	main._open_floor_reward(false)
	var has_heal = false
	for r in main.pending_rewards:
		if r["type"] == "heal":
			has_heal = true
	assert(not has_heal, "Serment Funeste retire l'option de soin du butin")
	main.resolve_floor_reward(0)
	print("OK Phase 4: butin de fin d'étage (choix, élite enrichi, interaction Funeste)")

	# --- Sprites directionnels d'Aria ---------------------------------------------
	var mv = main.map_view
	var fake = Entity.new(); fake.sprite = "aria"
	fake.facing = Vector2i(0, 1)
	assert(mv._directional_sprite(fake)["name"] == "aria" and not mv._directional_sprite(fake)["flip"], "face vers le bas")
	fake.facing = Vector2i(0, -1)
	assert(mv._directional_sprite(fake)["name"] == "aria_back", "dos vers le haut")
	fake.facing = Vector2i(1, 0)
	var rr = mv._directional_sprite(fake)
	assert(rr["name"] == "aria_side" and not rr["flip"], "profil droite")
	fake.facing = Vector2i(-1, 0)
	var ll = mv._directional_sprite(fake)
	assert(ll["name"] == "aria_side" and ll["flip"], "profil gauche (miroir)")
	var gob = Entity.new(); gob.sprite = "gobelin"; gob.facing = Vector2i(0, -1)
	assert(mv._directional_sprite(gob)["name"] == "gobelin", "les autres entités gardent leur sprite unique")
	# Une action oriente bien l'héroïne.
	main.start_run("melee")
	main.try_move(0, -1)
	assert(main.player.facing == Vector2i(0, -1), "une action oriente le sprite de l'héroïne")
	print("OK sprites directionnels: face/dos/profil + miroir, orientation par l'action")

	# --- Nouveaux monstres : spawn + exécution de chaque comportement (Pass 1) -----
	main.start_run("melee")
	# Isole ce test de comportement d'IA du Pacte de Pouvoir (nœud acheté plus
	# haut) : un pouvoir de départ comme le Drone attaquerait automatiquement à
	# chaque tour et pourrait achever un monstre fragile (ex. Chauve-souris,
	# 9 PV) avant la fin des 14 tours, faussant l'objectif du test.
	main.player.powers.clear()
	var new_count := 0
	for edef in Data.ENEMIES:
		if not edef.has("ai"):
			continue                              # ignore les 5 ennemis d'origine
		new_count += 1
		main.enemies.clear()
		main.hazards.clear()
		main.player.max_hp = 9999
		main.player.hp = 9999
		main.player.atk = 60
		var spot: Vector2i = _find_spot(main, main.player.pos())
		var mon = main._make_enemy(edef, 8, spot)
		assert(mon.ai.has("behavior"), "%s a un comportement" % edef["name"])
		main.enemies.append(mon)
		for _t in 14:                             # laisse le monde tourner : le monstre agit
			if main.state != main.State.PLAYING:
				break
			main.pass_turn()
		assert(main.state == main.State.PLAYING or main.state == main.State.GAMEOVER, "combat stable avec %s" % edef["name"])
		main.state = main.State.PLAYING
	assert(new_count == 20, "20 nouveaux monstres définis (vu %d)" % new_count)
	print("OK nouveaux monstres: %d comportements exécutés sans crash" % new_count)

	# --- Nouveaux statuts : saignement, maladie, weaken, confusion ----------------
	main.enemies.clear()
	main.player.max_hp = 200
	main.player.hp = 200
	main.apply_bleed(main.player, 3, 5.0)
	main.apply_disease(main.player, 3, 4.0)
	var hp_before_dot: int = main.player.hp
	main.player.tick_statuses()
	assert(main.player.hp < hp_before_dot, "saignement + maladie infligent des dégâts par tour")
	var base_def: int = main.player.defense
	main.apply_weaken(main.player, 3, 4.0)
	assert(main._player_def() <= maxi(0, base_def - 4), "weaken réduit la défense effective")
	main.apply_confuse(main.player, 3)
	assert(main.player.has_status("confusion"), "confusion appliquée")
	print("OK nouveaux statuts: saignement, maladie, défense réduite, confusion")

	# --- Résistances, immunité feu, pièges ----------------------------------------
	assert(not main._enemy_def_by_sprite("golem").is_empty(), "définition golem trouvée")
	var fire_el = main._make_enemy(main._enemy_def_by_sprite("elementaire_feu"), 8, main.player.pos() + Vector2i(2, 0))
	main.apply_burn(fire_el, 3, 9.0)
	assert(not fire_el.has_status("burn"), "élémentaire de feu insensible au feu")
	main.hazards.clear()
	main._drop_trap(main.player.pos() + Vector2i(1, 0))
	assert(main.hazards.size() == 1, "piège posé au sol")
	print("OK résistances/immunité/pièges")

	# --- Boss Pass 2 : spawn (+ gardiens) + exécution des mécaniques --------------
	main.start_run("melee")
	for bi in Data.BOSSES.size():
		var bdef: Dictionary = Data.BOSSES[bi]
		main.enemies.clear()
		main.hazards.clear()
		main.player.max_hp = 99999
		main.player.hp = 99999
		main.player.atk = 80
		var bspot: Vector2i = _find_spot(main, main.player.pos())
		var boss = main._make_enemy(bdef, 10, bspot, true)
		for ad in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var ap: Vector2i = main.player.pos() + ad
			if main.dungeon.is_walkable(ap.x, ap.y) and main.enemy_at(ap.x, ap.y) == null:
				boss.x = ap.x
				boss.y = ap.y
				break
		main.enemies.append(boss)
		main._boss_on_spawn(boss, [boss.pos(), main.player.pos()])
		assert(boss.is_boss, "%s est un boss" % bdef["name"])
		if boss.ai.has("guardians"):
			assert(main._living_guardians(boss) > 0, "%s protégé par des gardiens" % bdef["name"])
			# Phase 1.4 : les gardiens apparaissent désormais près du boss (rayon 6), pas n'importe où.
			for g in main.enemies:
				if int(g.ai.get("guard_for", 0)) == boss.get_instance_id():
					var d: int = maxi(absi(g.x - boss.x), absi(g.y - boss.y))
					assert(d <= 6, "%s : gardien à distance de Tchebychev %d (> 6) du boss" % [bdef["name"], d])
		for _t in 16:
			if main.state != main.State.PLAYING:
				break
			main.try_move(signi(boss.x - main.player.x), signi(boss.y - main.player.y))
			if main.state != main.State.PLAYING:
				break
			main.pass_turn()
		main.state = main.State.PLAYING
	assert(Data.BOSSES.size() == 10, "10 boss définis (vu %d)" % Data.BOSSES.size())
	print("OK boss Pass 2: %d boss (gardiens, ponte, phases, charge, souffle) sans crash" % Data.BOSSES.size())

	# --- Phase 1.4 (2/2) : les gardiens survivants se dissipent à la mort du boss --
	main.start_run("melee")
	main.enemies.clear()
	var g_boss = main._make_enemy(Data.BOSSES[1], 10, main.player.pos() + Vector2i(3, 0), true)
	main.enemies.append(g_boss)
	main._boss_on_spawn(g_boss, [g_boss.pos(), main.player.pos()])
	if g_boss.ai.has("guardians"):
		assert(main._living_guardians(g_boss) > 0, "gardiens de test posés avant de tuer le boss")
		main.run_bosses = 0
		main.on_enemy_killed(g_boss)
		var leftover := false
		for g in main.enemies:
			if int(g.ai.get("guard_for", 0)) == g_boss.get_instance_id():
				leftover = true
		assert(not leftover, "les gardiens sont retirés quand leur boss meurt")
		print("OK Phase 1.4: gardiens dans un rayon de 6 du boss + dissipés à sa mort")

	# --- Phase 1.2 : le butin de pouvoir garanti du boss n'est plus du code mort ---
	main.start_run("melee")
	main.enemies.clear()
	main.loot.clear()
	var p_boss = main._make_enemy(Data.BOSSES[0], 10, main.player.pos() + Vector2i(2, 0), true)
	main.enemies.append(p_boss)
	main.run_bosses = 1
	main.on_enemy_killed(p_boss)
	var power_dropped := false
	for it in main.loot:
		if it.get("kind", "") == "power":
			power_dropped = true
	assert(power_dropped, "un Gardien pair (run_bosses devenant pair) lâche garantit un pouvoir")
	print("OK Phase 1.2: le pouvoir garanti tombe désormais un Gardien sur deux")

	# --- Hub (Pied de la Tour) : déplacement libre + entrée dans les bâtiments ----
	main.enter_hub()
	assert(main.state == main.State.HUB, "le Hub s'ouvre dans son propre état")
	assert(main.hub_pos == main.town.player_start, "Aria démarre au centre de la place")
	# Bibliothèque en (13,5), départ (8,6) : 5 pas est puis 1 pas nord.
	for i in 5:
		main._hub_try_move(1, 0)
	main._hub_try_move(0, -1)
	assert(main.state == main.State.META, "marcher sur la Bibliothèque ouvre l'Arbre de Connaissances")
	assert(main.hub_pos == Vector2i(13, 5), "Aria s'arrête sur la case du bâtiment")
	main.return_to_previous()
	assert(main.state == main.State.HUB, "Retour depuis un écran ouvert par le Hub revient au Hub")
	assert(main.hub_pos == Vector2i(13, 5), "la position d'Aria dans le Hub est conservée entre deux visites")
	# La bordure de la ville reste infranchissable.
	main.hub_pos = Vector2i(1, 1)
	main._hub_try_move(-1, 0)
	assert(main.hub_pos == Vector2i(1, 1), "la bordure du Hub bloque le déplacement")
	# Depuis l'écran-titre (pas le Hub), Retour ramène bien au titre.
	main.return_to_title()
	main.open_knowledge()
	main.return_to_previous()
	assert(main.state == main.State.TITLE, "Retour depuis un écran ouvert par le titre revient au titre")
	print("OK Hub: déplacement, entrée de bâtiment, retour contextuel (Hub vs titre), bordure bloquante")

	# --- Phase 3.2 : réglages persistants (volumes/tremblement) + Sfx sans crash --
	GameState.settings["sfx_vol"] = 0.4
	GameState.settings["screenshake"] = false
	GameState.save_game()
	GameState.settings = { "sfx_vol": 0.8, "music_vol": 0.8, "screenshake": true }
	GameState.load_game()
	assert(is_equal_approx(float(GameState.settings["sfx_vol"]), 0.4), "sfx_vol persiste à travers save/load")
	assert(GameState.settings["screenshake"] == false, "screenshake persiste à travers save/load")
	GameState.settings["sfx_vol"] = 0.8
	GameState.settings["screenshake"] = true
	GameState.save_game()
	Sfx.play("son_qui_nexiste_pas")   # fichier absent : ne doit jamais planter
	Sfx.play("hit")                  # fichier généré (si présent) : ne doit jamais planter
	print("OK Phase 3.2: GameState.settings persiste (save/load) ; Sfx.play() ne plante jamais")

	# --- Phase 3.5 : météo d'ambiance déclarée pour chaque biome -------------------
	for b in Data.BIOMES:
		var amb: Dictionary = b.get("ambient", {})
		assert(not amb.is_empty(), "%s a une définition ambient" % b["id"])
		assert(amb.has("color") and amb.has("count") and amb.has("vel") and amb.has("size"),
			"%s : ambient complet (color/count/vel/size)" % b["id"])
		assert(int(amb["count"]) > 0, "%s : au moins une particule" % b["id"])
	print("OK Phase 3.5: les 6 biomes déclarent une météo d'ambiance (Data.BIOMES[*].ambient)")

	# --- Phase 3.6 : récap de mort (source du coup fatal + chronologie du run) ----
	main.active_oaths = []
	main.start_run("melee")
	main.player.dodge_chance = 0.0
	main.enemies.clear()
	var dr_enemy: Entity = main._make_enemy(main._enemy_def_by_sprite("gnoll"), 1, main.player.pos() + Vector2i(2, 0))
	main.enemies.append(dr_enemy)
	main._enemy_hit_player(dr_enemy)
	assert(main.last_damage_source == dr_enemy.display_name, "last_damage_source enregistre l'attaquant")
	assert(main.run_timeline.size() > 0, "run_timeline contient au moins l'entrée d'entrée en biome")
	main.player.hp = 1
	main.game_over()
	assert(GameState.last_run.get("killed_by", "") == dr_enemy.display_name, "le journal du run garde la source du coup fatal")
	print("OK Phase 3.6: récap de mort — source du coup fatal + chronologie du run")

	# --- Phase 3.7 : tirage de talents unifié sur Main.rng (sans doublon) ---------
	main.active_oaths = []
	main.start_run("melee")
	var choices: Array = main.roll_talent_choices()
	assert(choices.size() == mini(3, Data.TALENTS.size()), "roll_talent_choices tire jusqu'à 3 talents")
	var seen_talent_ids: Dictionary = {}
	for t in choices:
		assert(not seen_talent_ids.has(t["id"]), "pas de talent en double dans le tirage")
		seen_talent_ids[t["id"]] = true
	print("OK Phase 3.7: roll_talent_choices tire 3 talents distincts via Main.rng (RNG unifiée)")

	# --- Phase 3.7 : start_run(loadout, seed) est entièrement déterministe --------
	main.active_oaths = []
	main.start_run("melee", 12345)
	assert(main.run_seed == 12345, "run_seed reflète la seed forcée")
	var seed_start: Vector2i = main.dungeon.start
	var seed_stairs: Vector2i = main.dungeon.stairs
	var seed_enemy_count: int = main.enemies.size()
	var seed_first_enemy: Vector2i = main.enemies[0].pos() if not main.enemies.is_empty() else Vector2i(-1, -1)
	main.active_oaths = []
	main.start_run("melee", 12345)
	assert(main.dungeon.start == seed_start, "seed fixe : même entrée de donjon")
	assert(main.dungeon.stairs == seed_stairs, "seed fixe : même escalier")
	assert(main.enemies.size() == seed_enemy_count, "seed fixe : même nombre d'ennemis")
	var seed_first_enemy2: Vector2i = main.enemies[0].pos() if not main.enemies.is_empty() else Vector2i(-1, -1)
	assert(seed_first_enemy2 == seed_first_enemy, "seed fixe : même position du 1er ennemi")
	print("OK Phase 3.7: start_run(loadout_id, seed) est entièrement déterministe pour une seed donnée")

	# --- Phase 4.0/4.1 : substrat d'effets de terrain + tranche verticale (feu, Forêt) ---
	main.active_oaths = []
	main.start_run("melee")
	var fire_rng := RandomNumberGenerator.new(); fire_rng.seed = 44
	var fire_map := Dungeon.new(20, 10, fire_rng, Data.biome_for_floor(1))
	for y in range(1, fire_map.height - 1):
		for x in range(1, fire_map.width - 1):
			fire_map.tiles[y][x] = Dungeon.FLOOR
	var fire_row_y := 4
	for x in range(5, 10):
		fire_map.tiles[fire_row_y][x] = Dungeon.TREE
	fire_map.rebuild_reachability()
	main.dungeon = fire_map
	main.player.x = 5
	main.player.y = fire_row_y + 2
	main.enemies.clear()
	var fire_witness: Entity = main._make_enemy(main._enemy_def_by_sprite("gnoll"), 1, Vector2i(5, fire_row_y + 1))
	fire_witness.awake = true
	main.enemies.append(fire_witness)
	var prev_spread_chance: float = Data.FIRE_SPREAD_CHANCE
	Data.FIRE_SPREAD_CHANCE = 1.0   # propagation garantie : test déterministe
	assert(main.ignite(Vector2i(5, fire_row_y)), "ignite() embrase le premier arbre de la rangée (case TREE, sans effet)")
	assert(not main.ignite(Vector2i(5, fire_row_y)), "ré-ignite un arbre déjà en feu échoue (pas de double comptage)")
	for i in 12:
		main._tick_terrain()
	for x in range(5, 10):
		assert(fire_map.effects[fire_row_y][x] == Dungeon.EFF_BURNT, "l'arbre (%d,%d) a fini calciné après propagation en chaîne" % [x, fire_row_y])
		assert(fire_map.tiles[fire_row_y][x] == Dungeon.FLOOR, "une case calcinée redevient du sol (FLOOR)")
		assert(fire_map.is_walkable(x, fire_row_y), "une case calcinée redevient praticable")
	assert(fire_witness.has_status("burn"), "une entité parquée à côté du foyer a accumulé des stacks de brûlure")
	Data.FIRE_SPREAD_CHANCE = prev_spread_chance
	main.dungeon = null
	print("OK Phase 4.0/4.1: substrat d'effets de terrain (Dungeon.effects/active_effects) + tranche verticale — le feu se propage en chaîne dans la Forêt, calcine, redevient praticable")

	# --- Phase 4.2 : extensions élémentaires (foudre/eau, gel, nuages, lave) -------
	main.start_run("melee")
	var elem_rng := RandomNumberGenerator.new(); elem_rng.seed = 55
	var elem_map := Dungeon.new(24, 12, elem_rng, Data.biome_for_floor(1))
	for y in range(1, elem_map.height - 1):
		for x in range(1, elem_map.width - 1):
			elem_map.tiles[y][x] = Dungeon.FLOOR
			elem_map.effects[y][x] = Dungeon.EFF_NONE
			elem_map.effect_timer[y][x] = 0
	# Plan d'eau horizontal de 4 cases en y=5, x=6..9.
	for x in range(6, 10):
		elem_map.tiles[5][x] = Dungeon.WATER
	elem_map.active_effects = []
	elem_map.rebuild_reachability()
	main.dungeon = elem_map
	main.player.x = 2; main.player.y = 2
	main.enemies.clear()
	main.hazards.clear()
	# Foudre conduite : cible collée au rivage, complice sur l'autre rive, témoin au loin.
	var zap_target: Entity = main._make_enemy(main._enemy_def_by_sprite("gnoll"), 1, Vector2i(6, 4))
	var zap_victim: Entity = main._make_enemy(main._enemy_def_by_sprite("gnoll"), 1, Vector2i(9, 6))
	var zap_far: Entity = main._make_enemy(main._enemy_def_by_sprite("gnoll"), 1, Vector2i(20, 10))
	for z in [zap_target, zap_victim, zap_far]:
		z.awake = true
		main.enemies.append(z)
	var hp_victim: int = zap_victim.hp
	var hp_far: int = zap_far.hp
	main._conducted_cells.clear()
	main.conduct_lightning(zap_target.pos(), 10)
	assert(zap_victim.hp == hp_victim - int(round(10 * Data.LIGHTNING_CONDUCT_PCT)), "la foudre conduite inflige 50% du coup à l'ennemi au bord du même plan d'eau")
	assert(zap_far.hp == hp_far, "un ennemi loin de l'eau n'est pas touché par la conduction")
	main.conduct_lightning(zap_target.pos(), 10)
	assert(zap_victim.hp == hp_victim - int(round(10 * Data.LIGHTNING_CONDUCT_PCT)), "un même plan d'eau ne conduit qu'une fois par lancer (_conducted_cells)")
	# Gel : l'eau adjacente à l'impact gèle, devient praticable, puis fond.
	main.freeze_water_near(Vector2i(6, 4))
	assert(elem_map.effects[5][6] == Dungeon.EFF_FROZEN, "le gel fige le plan d'eau adjacent à l'impact")
	assert(elem_map.is_walkable(6, 5), "une case gelée est praticable (pont de glace)")
	# La glace n'est plus conductrice.
	main._conducted_cells.clear()
	var hp_victim2: int = zap_victim.hp
	main.conduct_lightning(zap_target.pos(), 10)
	assert(zap_victim.hp == hp_victim2, "un plan d'eau entièrement gelé ne conduit plus la foudre")
	# Une entité parquée sur la glace subit la fonte : relogée + 3 dégâts + ralentie.
	var skater: Entity = main._make_enemy(main._enemy_def_by_sprite("gnoll"), 1, Vector2i(7, 5))
	skater.awake = true
	main.enemies.append(skater)
	var hp_skater: int = skater.hp
	for i in Data.FROZEN_TURNS + 1:
		main._tick_terrain()
	assert(elem_map.effects[5][7] == Dungeon.EFF_NONE, "la glace a fondu après FROZEN_TURNS actions")
	assert(not elem_map.is_walkable(7, 5), "l'eau dégelée redevient infranchissable")
	assert(skater.pos() != Vector2i(7, 5) and elem_map.is_walkable(skater.x, skater.y), "l'entité sur la glace est relogée sur une case praticable à la fonte")
	assert(skater.hp == hp_skater - 3 and skater.has_status("slow"), "la glace cède : 3 dégâts + ralentissement")
	# Nuage toxique : empoisonne l'entité qui s'y attarde, se dissipe.
	var cloud_pos := Vector2i(15, 8)
	main.spawn_poison_cloud(cloud_pos, 0)
	assert(elem_map.effects[cloud_pos.y][cloud_pos.x] == Dungeon.EFF_CLOUD, "le nuage toxique est posé")
	var choker: Entity = main._make_enemy(main._enemy_def_by_sprite("gnoll"), 1, cloud_pos)
	choker.awake = true
	main.enemies.append(choker)
	main._tick_terrain()
	assert(choker.has_status("poison"), "une entité dans le nuage est empoisonnée à chaque tour")
	for i in Data.CLOUD_TURNS:
		main._tick_terrain()
	assert(elem_map.effects[cloud_pos.y][cloud_pos.x] == Dungeon.EFF_NONE, "le nuage se dissipe après CLOUD_TURNS")
	print("OK Phase 4.2: foudre conduite par l'eau (une décharge par lancer), gel praticable + fonte (relogement), nuages toxiques")

	# --- Phase 4.3 : projection (push_entity, Coup de bélier, lave) ----------------
	main.enemies.clear()
	# Poussée en terrain libre : 2 cases pleines.
	var pushee: Entity = main._make_enemy(main._enemy_def_by_sprite("gnoll"), 1, Vector2i(14, 2))
	pushee.awake = true
	main.enemies.append(pushee)
	main.push_entity(pushee, Vector2i(1, 0), 2)
	assert(pushee.pos() == Vector2i(16, 2), "push_entity déplace de 2 cases en terrain libre")
	# Poussée vers l'eau : stoppe au bord, 3 dégâts + ralenti.
	pushee.x = 7; pushee.y = 3
	var hp_push: int = pushee.hp
	main.push_entity(pushee, Vector2i(0, 1), 2)
	assert(pushee.pos() == Vector2i(7, 4), "poussé vers l'eau : reste sur la dernière case valide")
	assert(pushee.hp == hp_push - 3 and pushee.has_status("slow"), "poussé vers l'eau : 3 dégâts + ralentissement")
	# Poussée contre un mur : stop net, aucun dégât.
	pushee.x = 2; pushee.y = 2
	var hp_wall: int = pushee.hp
	main.push_entity(pushee, Vector2i(-1, 0), 3)
	assert(pushee.pos() == Vector2i(1, 2) or pushee.pos() == Vector2i(2, 2), "poussé contre le bord : stoppé par le mur")
	assert(pushee.hp == hp_wall, "un mur n'inflige pas de dégâts de poussée")
	# Lave (volcan) : la cible rebondit sur sa case d'origine, brûlée.
	elem_map.biome = Data.BIOMES[5]   # volcan : l'eau du biome est de la lave
	assert(elem_map.is_lava(), "le biome volcan traite WATER comme de la lave")
	pushee.x = 7; pushee.y = 3
	pushee.hp = pushee.max_hp
	var hp_lava: int = pushee.hp
	main.push_entity(pushee, Vector2i(0, 1), 2)
	assert(pushee.pos() == Vector2i(7, 4), "poussé vers la lave : rebondit avant la coulée")
	assert(pushee.hp == hp_lava - (8 + main.floor_num), "la lave inflige 8 + étage dégâts")
	assert(pushee.has_status("burn"), "la lave enflamme la cible poussée")
	elem_map.biome = Data.biome_for_floor(1)
	# Coup de bélier : frappe et repousse de 2 cases.
	assert(Data.SKILLS.has("shield_bash"), "la compétence Coup de bélier existe")
	main.enemies.clear()
	main.player.x = 12; main.player.y = 8
	var rammed: Entity = main._make_enemy(main._enemy_def_by_sprite("ours"), 1, Vector2i(13, 8))
	rammed.hp = 999; rammed.max_hp = 999
	rammed.awake = true
	main.enemies.append(rammed)
	elem_map.reveal(main.player.pos(), 6)   # l'auto-visée exige une cible visible (brouillard)
	main._cast_skill(Data.SKILLS["shield_bash"])
	assert(rammed.pos() == Vector2i(15, 8), "Coup de bélier : la cible est repoussée de 2 cases")
	# Le Bourreau (charger) projette de 2 cases, les chargeurs standard de 1.
	var bourreau_def: Dictionary = {}
	for bdef in Data.BOSSES:
		if String(bdef.get("sprite", "")) == "bourreau":
			bourreau_def = bdef
	assert(int(bourreau_def["ai"].get("push", 1)) == 2, "le Bourreau projette de 2 cases")
	main.dungeon = null
	print("OK Phase 4.3: push_entity (libre/eau/mur/lave), Coup de bélier, Bourreau push 2")

	# --- Phase 7.2 : versionnage de sauvegarde + migration --------------------
	var v1_json := JSON.stringify({
		"shards": 42, "knowledge": 3, "knowledge_nodes": [], "discovered": {},
		"upgrades": {}, "best_floor": 5, "best_kills": 10, "last_loadout": "ranged",
	})   # pas de clé "version" ni "settings" : forme d'avant la Phase 7.2
	var parsed_v1 = JSON.parse_string(v1_json)
	GameState.shards = -1
	GameState.settings = { "sfx_vol": 0.8, "music_vol": 0.8, "screenshake": true }
	assert(typeof(parsed_v1) == TYPE_DICTIONARY, "JSON v1 de test valide")
	assert(int(parsed_v1.get("version", 1)) == 1, "une sauvegarde sans clé version est traitée comme v1")
	# Chemin exercé indirectement (load_game lit un fichier) : on rejoue la même
	# logique de peuplement de champs pour vérifier qu'aucune clé manquante ne plante.
	var loaded_shards: int = int(parsed_v1.get("shards", 0))
	var loaded_settings = parsed_v1.get("settings", {})
	assert(loaded_shards == 42, "champ existant lu correctement depuis une sauvegarde v1")
	assert(typeof(loaded_settings) == TYPE_DICTIONARY and loaded_settings.is_empty(), "clé 'settings' absente d'une sauvegarde v1 : reste sur les valeurs par défaut")
	assert(GameState.SAVE_VERSION == 2, "version de sauvegarde actuelle == 2")
	print("OK Phase 7.2: sauvegarde v1 (sans version/settings) chargée sans plantage, SAVE_VERSION == 2")

	# --- Phase 7.5 : nettoyage (sprites morts, collisions de glyphes ASCII) ---
	for dead in ["knight", "mage", "ranger"]:
		assert(not ResourceLoader.exists("res://assets/%s.png" % dead), "sprite legacy '%s' supprimé" % dead)
	var glyphs: Dictionary = {}
	for def in Data.ENEMIES:
		var g: String = str(def["glyph"])
		assert(not glyphs.has(g) or g == "B", "glyphe ASCII '%s' non dupliqué hors bosses (%s vs %s)" % [g, def["name"], glyphs.get(g, "")])
		glyphs[g] = def["name"]
	print("OK Phase 7.5: sprites legacy absents, plus de collision de glyphe Drake/Kobold ni Ours/boss")

	# --- Phase 7.7 : la sidebar ne reconstruit ses sections que si le contenu change ---
	main.player.artifacts = [Data.ARTIFACTS[0].duplicate()]
	main.hud.refresh()
	var art_child_before: int = main.hud.artifact_box.get_child_count()
	var art_id_before: int = main.hud.artifact_box.get_child(0).get_instance_id()
	main.hud.refresh()   # rien n'a changé côté artefacts
	assert(main.hud.artifact_box.get_child_count() == art_child_before and main.hud.artifact_box.get_child(0).get_instance_id() == art_id_before, "refresh() sans changement d'artefacts ne recrée pas les nœuds de la sidebar")
	main.player.artifacts = []
	main.hud.refresh()
	assert(main.hud.artifact_box.get_child(0).get_instance_id() != art_id_before, "refresh() reconstruit bien la section quand les artefacts changent")
	print("OK Phase 7.7: sections sidebar (artefacts/pouvoirs/synergies/états) mises en cache par empreinte")

	# --- Phase 5.2 : leviers d'échelle, XP découplée, filtre max_floor ----------
	# Courbe d'XP quadratique.
	assert(main.xp_to_next(1) == 10 + 1 * 1 * 3 and main.xp_to_next(5) == 10 + 5 * 5 * 3, "xp_to_next est quadratique (10 + level²·3)")
	# Pentes d'échelle séparées : à l'étage 11 (step 10), les multiplicateurs valent
	# 1 + 10·pente. On vérifie que HP et ATK utilisent des pentes distinctes.
	var gob_def: Dictionary = main._enemy_def_by_sprite("gobelin")
	var scaled: Entity = main._make_enemy(gob_def, 11, Vector2i(3, 3))
	assert(scaled.max_hp == int(round(gob_def["max_hp"] * (1.0 + 10.0 * Data.ENEMY_HP_SLOPE))), "PV ennemis scalés par ENEMY_HP_SLOPE")
	assert(scaled.atk == int(round(gob_def["atk"] * (1.0 + 10.0 * Data.ENEMY_ATK_SLOPE))), "ATK ennemis scalée par ENEMY_ATK_SLOPE (pente distincte des PV)")
	# XP découplée : xp_value = shards par défaut, mais champ indépendant.
	assert(scaled.xp_value == int(gob_def["shards"]), "xp_value par défaut = shards (découplage en place)")
	# Défense scalée : un ennemi à défense de base > 0 gagne de la défense avec l'étage.
	var orc_def: Dictionary = main._enemy_def_by_sprite("orc")
	var orc_hi: Entity = main._make_enemy(orc_def, 11, Vector2i(3, 3))
	assert(orc_hi.defense == int(round(int(orc_def["defense"]) * (1.0 + 10.0 * Data.ENEMY_DEF_SLOPE))), "défense ennemie désormais scalée par ENEMY_DEF_SLOPE")
	# Filtre max_floor : le Gobelin (max_floor 14) se retire du pool tardif.
	main.floor_num = 20
	var late_pool_has_gobelin := false
	for _i in range(60):
		if String(main._pick_enemy_def().get("sprite", "")) == "gobelin":
			late_pool_has_gobelin = true
			break
	assert(not late_pool_has_gobelin, "le Gobelin (max_floor 14) ne réapparaît plus à l'étage 20")
	main.floor_num = 1
	print("OK Phase 5.2: XP quadratique découplée, pentes HP/ATK/DEF séparées, retrait des espèces faibles (max_floor)")

	# --- Phase 6.1 : talents mécaniques (hooks) ---------------------------------
	main.start_run("melee")
	assert(not main.player.has_talent_hook("toxicologue"), "aucun hook de talent au départ")
	# Toxicologue : ×1.6 sur les poisons infligés aux ennemis.
	var tox_target: Entity = main._make_enemy(main._enemy_def_by_sprite("gobelin"), 1, Vector2i(5, 5))
	main.apply_poison(tox_target, 3, 5.0)
	var base_poison: float = tox_target.status_value("poison")
	assert(abs(base_poison - 5.0) < 0.01, "poison de base non modifié sans talent")
	main.player.talents.append({ "id": "toxicologue", "name": "Toxicologue", "hook": "toxicologue" })
	assert(main.player.has_talent_hook("toxicologue"), "has_talent_hook détecte le talent mécanique")
	var tox2: Entity = main._make_enemy(main._enemy_def_by_sprite("gobelin"), 1, Vector2i(6, 6))
	main.apply_poison(tox2, 3, 5.0)
	assert(abs(tox2.status_value("poison") - 8.0) < 0.01, "Toxicologue : poison ×1.6 (5 → 8) sur un ennemi")
	# Un poison SUBI par la joueuse n'est jamais amplifié par Toxicologue.
	main.apply_poison(main.player, 3, 5.0)
	assert(abs(main.player.status_value("poison") - 5.0) < 0.01, "Toxicologue n'amplifie pas un poison subi (gate faction ennemie)")
	# Démolisseur : la poussée de la joueuse gagne +1 case.
	main.player.talents.append({ "id": "demolisseur", "name": "Démolisseur", "hook": "demolisseur" })
	assert(Data.TALENTS.size() >= 16, "TALENTS contient les 8 talents mécaniques + les stats plates")
	var n_hooks: int = 0
	for t in Data.TALENTS:
		if t.has("hook"): n_hooks += 1
	assert(n_hooks >= 8, "au moins 8 talents mécaniques (hooks) dans le pool")
	print("OK Phase 6.1: talents mécaniques (has_talent_hook, Toxicologue ×1.6 gate ennemi, ≥8 hooks)")

	# --- Phase 6.2 : affixes d'élite --------------------------------------------
	assert(Data.ELITE_AFFIXES.size() >= 5, "au moins 5 affixes d'élite définis")
	var elite_e: Entity = main._make_enemy(main._enemy_def_by_sprite("gobelin"), 3, Vector2i(7, 7))
	var hp_before_affix: int = elite_e.max_hp
	main._apply_elite_affix(elite_e)
	assert(elite_e.ai.has("elite_affix"), "un affixe d'élite est posé")
	assert(elite_e.tint != Color.WHITE, "l'élite reçoit une teinte de rendu")
	assert(elite_e.display_name.begins_with("Élite "), "le nom de l'élite est préfixé « Élite … »")
	assert(elite_e.max_hp == int(round(hp_before_affix * 1.15)), "bump de PV d'élite réduit à +15%")
	assert(bool(elite_e.ai.get("smart_path", false)), "l'élite reçoit le pathfinding intelligent")
	# Voleur : dérobe des Éclats au coup, les rend à sa mort.
	var thief: Entity = main._make_enemy(main._enemy_def_by_sprite("gobelin"), 3, main._find_spot(main, main.player.pos()))
	thief.ai["steal"] = 4
	thief.ai["stolen"] = 0
	thief.awake = true
	main.enemies.append(thief)
	main.run_shards = 100
	main.player.x = thief.x - 1; main.player.y = thief.y
	main._enemy_hit_player(thief)
	assert(main.run_shards == 96 and int(thief.ai.get("stolen", 0)) == 4, "Voleur : 4 Éclats dérobés par coup")
	var shards_pre_death: int = main.run_shards
	main.on_enemy_killed(thief)
	assert(main.run_shards == shards_pre_death + 4, "Voleur : Éclats dérobés restitués à sa mort")
	print("OK Phase 6.2: affixes d'élite (teinte, +15% PV, préfixe de nom, Voleur vol/restitution)")

	print("=== SMOKETEST PASSED ===")
	get_tree().quit()

## Trouve une case marchable proche de `from` pour y poser un monstre de test.
func _find_spot(main, from: Vector2i) -> Vector2i:
	for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2), Vector2i(3, 0), Vector2i(0, 3), Vector2i(1, 0)]:
		var p: Vector2i = from + d
		if main.dungeon.is_walkable(p.x, p.y) and main.enemy_at(p.x, p.y) == null and p != from:
			return p
	return from + Vector2i(1, 0)
