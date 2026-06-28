extends Node
# Test de fumée : pilote une vraie partie sans interaction. Lancé comme scène
# (les autoloads sont donc chargés -> GameState disponible).

func _ready() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)

	for hero in ["knight", "mage", "ranger"]:
		main.start_run(hero)
		assert(main.player != null and main.player.is_alive(), "joueur initialisé")
		var dirs = [[0, -1], [0, 1], [-1, 0], [1, 0]]
		for step in 300:
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
			main.next_floor()
			assert(main.floor_num >= 2, "montée d'étage")
		if main.state == main.State.PLAYING:
			main.floor_num = main.BOSS_EVERY - 1
			main.next_floor()
			var has_boss := false
			for e in main.enemies:
				if e.is_boss:
					has_boss = true
			assert(has_boss, "boss apparu")
		if main.state == main.State.PLAYING:
			var before = GameState.shards
			main.player.hp = 1
			main.run_shards = 7
			main.game_over()
			assert(main.state != main.State.PLAYING, "run terminé après la mort")
			assert(GameState.shards == before + 7, "éclats banqués à la mort")
		print("OK hero=%s floor=%d banque=%d" % [hero, main.floor_num, GameState.shards])

	# --- Test génération procédurale d'objets ---
	var grng = RandomNumberGenerator.new()
	grng.seed = 42
	var rarities_seen = {}
	for i in 200:
		var it = Data.generate_item("arme", 6, grng)
		assert(it["slot"] == "arme" and it.has("bonus") and it.has("rarity"), "objet généré valide")
		rarities_seen[it["rarity"]] = true
	assert(rarities_seen.size() >= 2, "plusieurs raretés générées")
	print("OK loot procédural: raretés vues = %s" % str(rarities_seen.keys()))

	# --- Test inventaire interactif ---
	main.start_run("knight")
	var atk0 = main.player.atk
	var sword = { "kind": "equip", "name": "Épée test", "slot": "arme", "salvage": 5, "bonus": { "atk": 5 } }
	main._bag_add(sword)
	assert(main.inventory.size() == 1, "objet ajouté au sac")
	main.equip_item(sword)
	assert(main.player.atk == atk0 + 5, "équipement applique le bonus")
	assert(main.inventory.size() == 0, "objet retiré du sac une fois équipé")
	main.unequip_item("arme")
	assert(main.player.atk == atk0 and main.inventory.size() == 1, "déséquipement rend l'objet au sac")
	var sb = main.run_shards
	main.salvage_item(sword)
	assert(main.run_shards == sb + 5 and main.inventory.is_empty(), "recyclage en éclats")
	# Consommable
	main.player.hp = 1
	var potion = { "kind": "consumable", "name": "Potion test", "effect": "heal_pct", "value": 0.5 }
	main._bag_add(potion)
	main.use_consumable(potion)
	assert(main.player.hp > 1 and main.inventory.is_empty(), "consommable soigne et se retire")
	print("OK inventaire: équiper/déséquiper/recycler/consommer")

	# --- Test artefact (capacité passive numérique) ---
	main._acquire_artifact({ "id": "lifesteal", "name": "Calice test", "desc": "vol de vie" })
	assert(main.player.lifesteal_pct > 0.0, "artefact -> stat dérivée")

	# --- Test montée de niveau & talents ---
	var tal0 = main.player.talents.size()
	main.player.xp = main.xp_to_next(main.player.level)
	main._check_level_up()
	assert(main.state == main.State.LEVELUP and main.pending_levelups >= 1, "level-up déclenché")
	main.pick_talent(Data.TALENTS[0])
	assert(main.player.talents.size() == tal0 + 1 and main.state == main.State.PLAYING, "talent appliqué, jeu repris")
	print("OK niveau/talents: niveau=%d talents=%d" % [main.player.level, main.player.talents.size()])

	# --- Test inventaire overlay (construction sans crash) ---
	main.open_inventory()
	assert(main.state == main.State.INVENTORY, "inventaire ouvert")
	main.close_inventory()
	assert(main.state == main.State.PLAYING, "inventaire fermé")
	print("OK overlay inventaire")

	GameState.shards = 1000
	var lvl_before = GameState.upgrade_level("vitalite")
	var bought = GameState.buy_upgrade("vitalite")
	assert(bought and GameState.upgrade_level("vitalite") == lvl_before + 1, "achat amélioration")
	print("OK boutique vitalite niv=%d" % GameState.upgrade_level("vitalite"))

	print("=== SMOKETEST PASSED ===")
	get_tree().quit()
