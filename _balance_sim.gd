extends SceneTree
# --- Harnais d'auto-jeu (Phase 5.1) -------------------------------------------
# Pilote N parties complètes avec une politique simple (pas d'IA fine : on veut
# une SONDE d'équilibrage reproductible, pas un joueur optimal) et écrit un CSV
# de mesures dans user://balance_sim.csv.
#
# Lancement :
#   godot --headless --path . --script res://_balance_sim.gd
#   SIM_RUNS=200 godot --headless --path . --script res://_balance_sim.gd
#
# GDScript sur des cartes 640×400 est lent : compter des minutes pour 50 runs —
# c'est la mesure elle-même. La politique désactive la méta (upgrades/nœuds de
# Connaissances/Serments) pour mesurer l'étage de mort médian SANS méta.
#
# Sortie CSV : seed,death_floor,killed_by,level,kills,turns,shards_banked,
#              best_rarity,stalled

const ACTION_CAP := 20000   # garde-fou anti-blocage : au-delà, run "stalled"

func _initialize() -> void:
	var runs: int = 50
	var env := OS.get_environment("SIM_RUNS")
	if env != "" and env.is_valid_int():
		runs = maxi(1, env.to_int())

	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)

	# Méta neutralisée : on mesure la difficulté brute, sans progression méta.
	_reset_meta()

	var rows: Array = []
	var death_floors: Array = []
	print("=== BALANCE SIM : %d run(s) ===" % runs)
	for i in range(runs):
		var seed_i: int = 1000 + i
		var row: Dictionary = _play_one_run(main, seed_i)
		rows.append(row)
		death_floors.append(int(row["death_floor"]))
		print("run %d/%d  seed=%d  étage=%d  niv=%d  kills=%d  tours=%d  %s" % [
			i + 1, runs, seed_i, int(row["death_floor"]), int(row["level"]),
			int(row["kills"]), int(row["turns"]),
			"STALLED" if bool(row["stalled"]) else "mort"])

	_write_csv(rows)
	death_floors.sort()
	print("--- étage de mort : p25=%d  p50=%d  p75=%d ---" % [
		_percentile(death_floors, 0.25), _percentile(death_floors, 0.50), _percentile(death_floors, 0.75)])
	print("=== BALANCE SIM DONE (%s) ===" % "user://balance_sim.csv")
	quit()

func _reset_meta() -> void:
	for key in Data.UPGRADE_ORDER:
		GameState.upgrades[key] = 0
	GameState.knowledge_nodes = []
	GameState.shards = 0
	GameState.knowledge = 0

## Joue une partie du début à la mort (ou au plafond d'actions). Renvoie la ligne
## de mesures. Ne touche jamais au rendu : tout passe par l'API logique de Main.
func _play_one_run(main, seed_i: int) -> Dictionary:
	main.active_oaths = []
	main.start_run("melee", seed_i)
	var shards_before: int = GameState.shards
	var turns: int = 0
	var best_rarity: int = 0
	var stalled: bool = false

	while main.state != main.State.GAMEOVER:
		if turns >= ACTION_CAP:
			stalled = true
			# Force une fin de run propre pour banquer et enregistrer les stats.
			main.last_damage_source = "l'épuisement (stalled)"
			main.game_over()
			break
		match main.state:
			main.State.PLAYING:
				_act_playing(main)
				turns += 1
			main.State.CHOICE:
				best_rarity = maxi(best_rarity, _act_choice(main))
			main.State.LEVELUP:
				_act_levelup(main)
			main.State.INVENTORY:
				main.close_inventory()   # ne jamais rester dans l'inventaire
			_:
				# État inattendu (TITLE/HUB/PAUSED…) : abandonne ce run proprement.
				main.last_damage_source = "un état inattendu"
				main.game_over()
				break

	best_rarity = maxi(best_rarity, _equipped_best_rarity(main))
	var lr: Dictionary = GameState.last_run
	return {
		"seed": seed_i,
		"death_floor": int(lr.get("floor", main.floor_num)),
		"killed_by": str(lr.get("killed_by", "")),
		"level": int(lr.get("level", main.player.level)),
		"kills": int(lr.get("kills", 0)),
		"turns": turns,
		"shards_banked": GameState.shards - shards_before,
		"best_rarity": best_rarity,
		"stalled": stalled,
	}

# --- Politiques par état ------------------------------------------------------

func _act_playing(main) -> void:
	var player = main.player
	# 1) Boire un soin si PV < 35%.
	if player.hp < int(player.max_hp * 0.35):
		var heal_item: Dictionary = _find_heal_consumable(main)
		if not heal_item.is_empty():
			main.use_consumable(heal_item)
			return
	# 2) Capacité prête + ennemi visible à portée ? On lance.
	if player.ability_ready() and main._nearest_enemy_in_range(player.ability_range) != null:
		main.use_ability()
		return
	# 3) Sinon on avance vers l'ennemi visible le plus proche, sinon vers l'escalier.
	var target: Vector2i = _nearest_visible_enemy_pos(main)
	if target == main.NO_TILE:
		target = main.dungeon.stairs
	var step: Vector2i = main.dungeon.next_step(player.pos(), target)
	if step == player.pos():
		# Pas de progrès A* : petit pas glouton pour se décoincer.
		var d: Vector2i = _sign_vec(target - player.pos())
		main.try_move(d.x, d.y)
	else:
		main.try_move(step.x - player.x, step.y - player.y)

## Renvoie le rang de rareté de l'objet éventuellement équipé (best_rarity).
func _act_choice(main) -> int:
	match main.current_choice:
		"reward":
			return _choose_reward(main)
		"shop":
			# Achète un soin si PV < 50% et abordable, sinon on part.
			if main.player.hp < int(main.player.max_hp * 0.5) and main.run_shards >= 15:
				main.buy_shop_heal()
			main.leave_shop()
		"event":
			main.resolve_event(0)
		"rest":
			main.rest_choice("heal")
		_:
			# Sécurité : type de choix inconnu → tente de sortir par une récompense 0.
			if not main.pending_rewards.is_empty():
				main.resolve_floor_reward(0)
	return 0

func _choose_reward(main) -> int:
	var rewards: Array = main.pending_rewards
	var equip_idx: int = -1
	var heal_idx: int = -1
	var shard_idx: int = -1
	for i in range(rewards.size()):
		match String(rewards[i].get("type", "")):
			"equip": equip_idx = i
			"heal": heal_idx = i
			"shards": shard_idx = i
	# Équipe si la pièce bat celle du slot correspondant.
	if equip_idx >= 0:
		var item: Dictionary = rewards[equip_idx]["data"]
		var slot: String = String(item.get("slot", ""))
		var cur_rank: int = main._rarity_rank(main.player.equipment.get(slot, {}))
		if main._rarity_rank(item) > cur_rank:
			main.resolve_floor_reward(equip_idx)
			# resolve_floor_reward ne fait que ranger : on équipe depuis le sac.
			for it in main.inventory.duplicate():
				if it == item:
					main.equip_item(it)
					break
			return main._rarity_rank(item)
	if heal_idx >= 0 and main.player.hp < int(main.player.max_hp * 0.6):
		main.resolve_floor_reward(heal_idx)
		return 0
	if shard_idx >= 0:
		main.resolve_floor_reward(shard_idx)
		return 0
	main.resolve_floor_reward(0)
	return 0

func _act_levelup(main) -> void:
	var choices: Array = main.roll_talent_choices()
	if choices.is_empty():
		# Filet de sécurité : pioche direct dans Data si l'offre est vide.
		main.pick_talent(Data.TALENTS[0])
	else:
		main.pick_talent(choices[0])

# --- Helpers ------------------------------------------------------------------

func _find_heal_consumable(main) -> Dictionary:
	for it in main.inventory:
		if it.get("kind", "") == "consumable":
			var eff: String = String(it.get("effect", ""))
			if eff == "heal_pct" or eff == "heal_full":
				return it
	return {}

func _nearest_visible_enemy_pos(main) -> Vector2i:
	var best: Vector2i = main.NO_TILE
	var best_d: int = 1 << 30
	for e in main.enemies:
		if not e.is_alive():
			continue
		if not main.dungeon.is_visible(e.x, e.y):
			continue
		if e.ai.get("behavior", "") == "ambush" and not e.revealed:
			continue
		var d: int = main._manhattan(main.player.pos(), e.pos())
		if d < best_d:
			best_d = d
			best = e.pos()
	return best

func _equipped_best_rarity(main) -> int:
	var best: int = 0
	for slot in main.player.equipment:
		best = maxi(best, main._rarity_rank(main.player.equipment[slot]))
	return best

func _sign_vec(v: Vector2i) -> Vector2i:
	return Vector2i(signi(v.x), signi(v.y))

func _percentile(sorted_vals: Array, q: float) -> int:
	if sorted_vals.is_empty():
		return 0
	var idx: int = clampi(int(floor(q * (sorted_vals.size() - 1))), 0, sorted_vals.size() - 1)
	return int(sorted_vals[idx])

func _write_csv(rows: Array) -> void:
	var f := FileAccess.open("user://balance_sim.csv", FileAccess.WRITE)
	if f == null:
		push_error("balance_sim : impossible d'ouvrir user://balance_sim.csv")
		return
	f.store_line("seed,death_floor,killed_by,level,kills,turns,shards_banked,best_rarity,stalled")
	for r in rows:
		var killed: String = String(r["killed_by"]).replace(",", " ").replace("\n", " ")
		f.store_line("%d,%d,%s,%d,%d,%d,%d,%d,%d" % [
			int(r["seed"]), int(r["death_floor"]), killed, int(r["level"]),
			int(r["kills"]), int(r["turns"]), int(r["shards_banked"]),
			int(r["best_rarity"]), 1 if bool(r["stalled"]) else 0])
	f.close()
