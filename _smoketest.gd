extends Node
# Test de fumée : pilote une vraie partie sans interaction. Lancé comme scène
# (les autoloads sont donc chargés -> GameState disponible).

func _ready() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)

	# --- Parties complètes pour chaque héros (via la carte) ---
	for hero in ["knight", "mage", "ranger"]:
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
			assert(main.state == main.State.HUB, "retour au hub après la mort")
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
	main.start_run("knight")
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
	assert(main.state == main.State.MAP or main.state == main.State.HUB, "événement résolu")
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
	main.start_run("knight")
	main.choose_map_node(main.reachable_indices()[0])     # -> PLAYING
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
	var lvl_before = GameState.upgrade_level("vitalite")
	assert(GameState.buy_upgrade("vitalite") and GameState.upgrade_level("vitalite") == lvl_before + 1, "achat amélioration méta")
	print("OK boutique méta vitalite niv=%d" % GameState.upgrade_level("vitalite"))

	print("=== SMOKETEST PASSED ===")
	get_tree().quit()
