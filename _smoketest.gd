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
				main.end_turn()
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

	GameState.shards = 1000
	var lvl_before = GameState.upgrade_level("vitalite")
	var bought = GameState.buy_upgrade("vitalite")
	assert(bought and GameState.upgrade_level("vitalite") == lvl_before + 1, "achat amélioration")
	print("OK boutique vitalite niv=%d" % GameState.upgrade_level("vitalite"))

	print("=== SMOKETEST PASSED ===")
	get_tree().quit()
