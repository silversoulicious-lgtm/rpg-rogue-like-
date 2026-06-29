extends Node
# Test de fumée : pilote une vraie partie sans interaction. Lancé comme scène
# (les autoloads sont donc chargés -> GameState disponible).

func _ready() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)

	# --- Parties complètes pour chaque héros (via la carte) ---
	for hero in ["melee", "ranged", "magic"]:
		main.start_run(hero)
		assert(main.state == main.State.MAP, "run démarre sur la carte")
		var reach = main.reachable_indices()
		assert(reach.size() > 0, "nœuds accessibles au départ")
		main.choose_map_node(reach[0])               # rangée 0 = combat
		assert(main.state == main.State.PLAYING, "entrée en combat")
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

	# --- Carte de strate : structure & connectivité ---
	var mrng = RandomNumberGenerator.new(); mrng.seed = 5
	var rm = RunMap.new(0, mrng)
	assert(rm.nodes.size() == RunMap.ROWS, "nombre de rangées")
	assert(rm.nodes[0][0]["type"] == "combat", "première rangée = combat")
	assert(rm.nodes[RunMap.ROWS - 1].size() == 1 and rm.nodes[RunMap.ROWS - 1][0]["type"] == "boss", "boss au sommet")
	for r in range(1, RunMap.ROWS):
		for j in rm.nodes[r].size():
			var has_parent = false
			for n in rm.nodes[r - 1]:
				if n["edges"].has(j):
					has_parent = true
					break
			assert(has_parent, "chaque nœud est relié (pas d'orphelin)")
	print("OK carte: %d rangées, graphe connecté" % rm.nodes.size())

	# --- Salles spéciales : boutique / événement / repos ---
	main.start_run("melee")
	main.run_shards = 9999
	main.open_shop()
	assert(main.state == main.State.CHOICE and main.shop_stock.size() > 0, "boutique ouverte")
	var stock0 = main.shop_stock.size()
	main.buy_shop_item(main.shop_stock[0])
	assert(main.shop_stock.size() == stock0 - 1, "achat retire l'objet du stock")
	main.leave_shop()
	assert(main.state == main.State.MAP, "retour carte après boutique")
	main.open_event()
	assert(main.state == main.State.CHOICE, "événement ouvert")
	main.resolve_event(0)
	assert(main.state == main.State.MAP or main.state == main.State.GAMEOVER, "événement résolu")
	main.open_rest()
	var atk_r = main.player.atk
	main.rest_choice("train")
	assert(main.player.atk == atk_r + 3 and main.state == main.State.MAP, "repos: entraînement +3 ATK")
	print("OK salles spéciales: boutique / événement / repos")

	# --- Génération procédurale d'objets ---
	var grng = RandomNumberGenerator.new(); grng.seed = 42
	var rarities_seen = {}
	for i in 200:
		var it = Data.generate_item("arme", 6, grng)
		assert(it["slot"] == "arme" and it.has("bonus") and it.has("rarity"), "objet généré valide")
		rarities_seen[it["rarity"]] = true
	assert(rarities_seen.size() >= 2, "plusieurs raretés générées")
	print("OK loot procédural: raretés vues = %s" % str(rarities_seen.keys()))

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
	main.choose_map_node(main.reachable_indices()[0])     # -> PLAYING
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
	main.choose_map_node(main.reachable_indices()[0])   # -> PLAYING (dungeon + ennemis)
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
	main.choose_map_node(main.reachable_indices()[0])
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
	main.choose_map_node(main.reachable_indices()[0])   # -> PLAYING (nécessaire pour pass_turn)
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

	print("=== SMOKETEST PASSED ===")
	get_tree().quit()
