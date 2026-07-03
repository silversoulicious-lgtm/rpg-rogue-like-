extends RefCounted
## Phase 7.3 (guide d'implémentation) : progression de run extraite de Main.gd.
## Module RefCounted détenant une back-reference vers Main (`game`) ; tout
## l'état partagé (player, floor_num, map_act, rng...) reste sur Main et est
## lu/écrit via `game.`.

var game: Node2D

func _init(g: Node2D) -> void:
	game = g

func _roll_node_type() -> String:
	if game.act_floor >= game.ACT_LENGTH:
		return "boss"
	if game.act_floor == game.ACT_LENGTH - 1 and not game._act_rest_done:
		game._act_rest_done = true
		return "rest" if game.rng.randf() < 0.5 else "shop"
	var elite_bonus: float = minf(0.12, game.map_act * 0.015)
	var combat_top: float = maxf(0.46, 0.58 - elite_bonus)
	var elite_top: float = combat_top + 0.15 + elite_bonus
	var shop_top: float = elite_top + 0.08
	var event_top: float = shop_top + 0.08
	var roll: float = game.rng.randf()
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
	game.hud.hide_overlay()
	game.refresh()
	var t: String = forced_type if forced_type != "" else _roll_node_type()
	match t:
		"shop":
			open_shop()
		"event":
			open_event()
		"rest":
			open_rest()
		_:
			game.current_node_type = t
			game.floor_num += 1
			game.act_floor += 1
			game.state = game.State.PLAYING
			game.hud.show_game()
			game.generate_floor(game.current_node_type)

func _node_cleared() -> void:
	Sfx.play("stairs")
	if game.current_node_type == "boss":
		var healed: int = 0 if game.has_oath("funeste") else int(round(game.player.max_hp * 0.2))
		game.player.heal(healed)
		game.map_act += 1
		game.act_floor = 0
		game._act_rest_done = false
		game.add_message("[color=#9b8cff]★ Gardien vaincu ! Tu poursuis l'ascension.[/color]")
		_advance("combat")
		return
	# Combat / élite : récompense de fin d'étage au choix (Phase 4).
	game.add_message("[color=#9b8cff]Voie dégagée. Choisis ta récompense.[/color]")
	_open_floor_reward(game.current_node_type == "elite")

# --- Récompense de fin d'étage (Phase 4) --------------------------------------
func _open_floor_reward(is_elite: bool) -> void:
	game.pending_rewards = _make_floor_rewards(is_elite)
	game.state = game.State.CHOICE
	game.current_choice = "reward"
	game.hud.show_floor_reward(game.pending_rewards, is_elite)

## Construit le butin de fin d'étage : soin, équipement, Éclats (+ bonus élite),
## mis à l'échelle de l'étage. Le Serment Funeste retire l'option de soin.
func _make_floor_rewards(is_elite: bool) -> Array:
	var rewards: Array = []
	var lvl: int = game.floor_num + (4 if is_elite else 0)
	if not game.has_oath("funeste"):
		var pct: float = 0.45 if is_elite else 0.30
		rewards.append({ "type": "heal", "value": pct, "color": Color(0.4, 0.9, 0.45),
			"label": "❤ Soin — +%d%% PV" % int(pct * 100),
			"desc": "Récupère une partie de tes points de vie." })
	var slot: String = Data.SLOTS[game.rng.randi_range(0, Data.SLOTS.size() - 1)]
	var item: Dictionary = Data.generate_item(slot, lvl, game.rng)
	var idesc: String = "%s — %s" % [item.get("rarity_name", ""), Data.bonus_summary(item["bonus"])]
	if item.get("desc", "") != "":
		idesc += " — " + String(item["desc"])
	rewards.append({ "type": "equip", "data": item, "color": item.get("rarity_color", Color.WHITE),
		"label": "%s %s" % [Data.SLOT_GLYPH[slot], item["name"]],
		"desc": idesc })
	var amt: int = (8 + game.floor_num * 3) * (2 if is_elite else 1)
	rewards.append({ "type": "shards", "value": amt, "color": Color(1.0, 0.85, 0.35),
		"label": "✦ %d Éclats" % amt,
		"desc": "Monnaie pour la boutique et le Sanctuaire." })
	# Bonus d'élite : un parchemin de compétence si possible, sinon un consommable.
	if is_elite:
		var sid: String = game._pick_droppable_skill()
		if sid != "":
			rewards.append({ "type": "skill", "data": sid, "color": Data.skill_rarity_color(sid),
				"label": "✦ Parchemin — %s" % Data.SKILLS[sid]["name"],
				"desc": String(Data.SKILLS[sid]["desc"]) })
		else:
			rewards.append(_consumable_reward())
	return rewards

func _consumable_reward() -> Dictionary:
	var c: Dictionary = Data.generate_consumable(game.floor_num, game.rng)
	return { "type": "consumable", "data": c, "color": c.get("color", Color.WHITE),
		"label": "! %s" % c["name"], "desc": "Objet à usage unique." }

func resolve_floor_reward(idx: int) -> void:
	if idx < 0 or idx >= game.pending_rewards.size():
		return
	var r: Dictionary = game.pending_rewards[idx]
	match String(r["type"]):
		"heal":
			var amt: int = int(round(game.player.max_hp * float(r["value"])))
			game.player.heal(amt)
			game.add_message("[color=#7aff8a]Récompense : +%d PV.[/color]" % amt)
		"shards":
			game.run_shards += int(r["value"])
			game.add_message("[color=#ffd24a]Récompense : +%d Éclats.[/color]" % int(r["value"]))
		"equip":
			game._bag_add(r["data"])
		"consumable":
			game._bag_add(r["data"])
		"skill":
			game._acquire_skill(String(r["data"]))
	game.pending_rewards = []
	_advance()

# --- Boutique -------------------------------------------------------------------
func open_shop() -> void:
	game.state = game.State.CHOICE
	game.current_choice = "shop"
	game.shop_stock = []
	for i in 3:
		var slot: String = Data.SLOTS[game.rng.randi_range(0, Data.SLOTS.size() - 1)]
		var it: Dictionary = Data.generate_item(slot, game.floor_num + 1, game.rng)
		it["price"] = int(it["salvage"] * 2.5)
		game.shop_stock.append(it)
	for i in 2:
		var c: Dictionary = Data.generate_consumable(game.floor_num, game.rng)
		c["price"] = 8 + game.floor_num
		game.shop_stock.append(c)
	if GameState.shop_always_power() or game.rng.randf() < 0.5:
		var pdef: Dictionary = game._pick_power_def()
		if not pdef.is_empty():
			var pitem: Dictionary = pdef.duplicate(true)
			pitem["kind"] = "power"
			pitem["price"] = 40
			game.shop_stock.append(pitem)
	game.hud.show_shop(game.shop_stock, game.run_shards)

func buy_shop_item(item: Dictionary) -> void:
	var price: int = int(item.get("price", 99999))
	if game.run_shards < price or not game.shop_stock.has(item):
		return
	game.run_shards -= price
	game.shop_stock.erase(item)
	Sfx.play("buy")
	if item.get("kind", "") == "power":
		game._acquire_power(item)
	else:
		game._bag_add(item)
	game.hud.show_shop(game.shop_stock, game.run_shards)

func buy_shop_heal() -> void:
	var price := 15
	if game.run_shards < price:
		return
	game.run_shards -= price
	Sfx.play("buy")
	game.player.heal(int(game.player.max_hp * 0.5))
	game.add_message("Soin à la boutique (+50% PV).")
	game.hud.show_shop(game.shop_stock, game.run_shards)

func leave_shop() -> void:
	_advance()

# --- Événement ----------------------------------------------------------------
func open_event() -> void:
	game.state = game.State.CHOICE
	game.current_choice = "event"
	# Phase 6.3 : les événements thématiques (champ "biome") ne sortent que dans
	# le biome de l'étage À VENIR ; les génériques (sans "biome") sont toujours
	# éligibles. Les événements se déclenchent entre deux étages.
	# L'étage à venir reste dans la strate courante (seul un Gardien change de
	# strate, jamais un événement) — on gate donc sur le biome de la strate.
	var upcoming: String = String(Data.biome_for_act(game.map_act).get("id", ""))
	var pool: Array = []
	for ev in Data.EVENTS:
		var b: String = String(ev.get("biome", ""))
		if b == "" or b == upcoming:
			pool.append(ev)
	if pool.is_empty():
		pool = Data.EVENTS
	game.current_event = pool[game.rng.randi_range(0, pool.size() - 1)]
	game.hud.show_event(game.current_event)

func resolve_event(choice_idx: int) -> void:
	_apply_event_effect(game.current_event["choices"][choice_idx])
	if not game.player.is_alive():
		game.game_over()
		return
	_advance()

func _apply_event_effect(ch: Dictionary) -> void:
	match ch.get("type", "none"):
		"heal":
			var a: int = int(game.player.max_hp * float(ch["value"]))
			game.player.heal(a)
			game.add_message("Tu récupères %d PV." % a)
		"item_consumable":
			game._bag_add(Data.generate_consumable(game.floor_num, game.rng))
		"shards":
			game.run_shards += int(ch["value"])
			game.add_message("+%d Éclats." % int(ch["value"]))
		"gamble":
			# Phase 5.2 : vrai pari — 55% gain, 45% perte de 15% des PV max (met
			# vraiment en jeu, indépendamment de l'étage grâce au pourcentage).
			if game.rng.randf() < 0.55:
				game.run_shards += 25
				game.add_message("[color=#9fff9f]Chance ! +25 Éclats.[/color]")
			else:
				game.last_damage_source = str(game.current_event.get("title", "un événement"))
				var loss: int = maxi(1, int(round(game.player.max_hp * 0.15)))
				game.player.take_damage(loss)
				game.add_message("[color=#ff8a8a]Piège ! −%d PV (15%%).[/color]" % loss)
		"trade_artifact":
			if game.run_shards >= 20:
				var a: Dictionary = game._pick_artifact_def()
				if not a.is_empty():
					game.run_shards -= 20
					game._acquire_artifact(a)
				else:
					game.add_message("Le marchand n'a plus rien pour toi.")
			else:
				game.add_message("Pas assez d'Éclats.")
		"stat_atk":
			game.player.base_atk += 3
			game.player.recompute_stats()
			game.add_message("Entraînement : +3 ATK (ce run).")
		"stat_hp":
			game.player.base_max_hp += 15
			game.player.recompute_stats()
			game.player.heal(15)
			game.add_message("Trempe : +15 PV max (ce run).")
		"stat_regen":
			game.player.base_hp_regen += 1
			game.player.recompute_stats()
			game.add_message("Méditation : +1 Régén PV/tour (ce run).")
		"cursed_altar":
			game.player.base_atk += 5
			game.player.base_max_hp = max(10, game.player.base_max_hp - 10)
			game.player.recompute_stats()
			game.add_message("[color=#ff8a8a]Autel maudit : +5 ATK mais −10 PV max (ce run).[/color]")
		"buy_revive":
			if game.run_shards >= 15:
				game.run_shards -= 15
				game.player.talents.append({ "name": "Bénédiction", "mods": { "max_revives": 1 } })
				game.player.recompute_stats()
				game.add_message("[color=#ffd24a]Bénédiction : +1 résurrection.[/color]")
			else:
				game.add_message("Pas assez d'Éclats.")
		_:
			game.add_message("Tu passes ton chemin.")

# --- Repos (feu de camp) ------------------------------------------------------
func open_rest() -> void:
	game.state = game.State.CHOICE
	game.current_choice = "rest"
	game.hud.show_rest()

func rest_choice(kind: String) -> void:
	match kind:
		"heal":
			var amt: int = int(game.player.max_hp * 0.4)
			game.player.heal(amt)
			if game.map_view != null:
				game.map_view.fx_damage(game.player.pos(), amt, "heal")
			game.add_message("Repos : +%d PV." % amt)
			_advance()
		"forge":
			open_forge()
		_:
			game.player.base_atk += 3
			game.player.recompute_stats()
			game.add_message("Entraînement : +3 ATK (ce run).")
			_advance()

## Forge Itinérante (rest_choice "forge") : ouvre l'écran de choix de la pièce
## d'équipement à renforcer plutôt que d'en tirer une au hasard en silence.
func open_forge() -> void:
	if game.player.equipment.is_empty():
		game.add_message("La forge reste froide : aucune pièce à renforcer.")
		_advance()
		return
	game.state = game.State.CHOICE
	game.hud.show_forge(game.player.equipment)

## Renforce de ~30% les bonus de la pièce d'équipement choisie à la Forge.
func forge_choice(slot: String) -> void:
	if not game.player.equipment.has(slot):
		_advance()
		return
	var it: Dictionary = game.player.equipment[slot]
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
	game.player.equipment[slot] = it
	game.player.recompute_stats()
	game.add_message("[color=#ffd24a]Forge : %s renforcé ![/color]" % it.get("name", "ton équipement"))
	_advance()

## Annule le passage à la Forge et revient au choix du feu de camp.
func forge_cancel() -> void:
	open_rest()
