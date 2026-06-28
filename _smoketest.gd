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

	# --- Test équipement + artefacts ---
	main.start_run("knight")
	var atk0 = main.player.atk
	var def0 = main.player.defense
	# Équipe une arme +ATK puis une armure +DEF
	var sword = { "name": "Épée test", "slot": "arme", "salvage": 3, "bonus": { "atk": 5 } }
	main._acquire_equipment(sword)
	assert(main.player.atk == atk0 + 5, "bonus arme appliqué")
	var armor = { "name": "Plastron test", "slot": "armure", "salvage": 3, "bonus": { "defense": 4, "max_hp": 10 } }
	var hp_before = main.player.max_hp
	main._acquire_equipment(armor)
	assert(main.player.defense == def0 + 4, "bonus armure DEF appliqué")
	assert(main.player.max_hp == hp_before + 10, "bonus armure PV appliqué")
	# Remplacement par une meilleure arme -> recyclage en éclats
	var shards_before = main.run_shards
	main._acquire_equipment({ "name": "Lame test", "slot": "arme", "salvage": 7, "bonus": { "atk": 9 } })
	assert(main.player.atk == atk0 + 9, "remplacement par meilleure arme")
	assert(main.run_shards == shards_before + 3, "ancienne arme recyclée en éclats")
	# Artefact : capacité passive active
	main._acquire_artifact({ "id": "lifesteal", "name": "Calice test", "desc": "vol de vie" })
	assert(main.player.has_artifact("lifesteal"), "artefact actif")
	print("OK équipement+artefacts: ATK=%d DEF=%d artefacts=%d" % [main.player.atk, main.player.defense, main.player.artifacts.size()])

	GameState.shards = 1000
	var lvl_before = GameState.upgrade_level("vitalite")
	var bought = GameState.buy_upgrade("vitalite")
	assert(bought and GameState.upgrade_level("vitalite") == lvl_before + 1, "achat amélioration")
	print("OK boutique vitalite niv=%d" % GameState.upgrade_level("vitalite"))

	print("=== SMOKETEST PASSED ===")
	get_tree().quit()
