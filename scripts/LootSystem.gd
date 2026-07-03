extends RefCounted
## Phase 7.3 (guide d'implémentation) : système de butin extrait de Main.gd.
## Module RefCounted détenant une back-reference vers Main (`game`) ; tout
## l'état partagé (player, loot, inventory, rng, floor_num...) reste sur
## Main et est lu/écrit via `game.`.

var game: Node2D

func _init(g: Node2D) -> void:
	game = g

func _spawn_loot(p: Vector2i, force_good: bool = false) -> void:
	var roll: float = game.rng.randf()
	var adef: Dictionary = {}
	if roll < 0.18 and not force_good:
		adef = _pick_artifact_def()
	if not adef.is_empty():
		game.loot.append({ "pos": p, "kind": "artifact", "glyph": Data.ARTIFACT_GLYPH,
			"sprite": "artifact", "color": adef["color"], "data": adef })
	elif roll < 0.42 and not force_good:
		var c: Dictionary = Data.generate_consumable(game.floor_num, game.rng)
		game.loot.append({ "pos": p, "kind": "consumable", "glyph": "!",
			"sprite": "potion", "color": c["color"], "data": c })
	else:
		# l'élite force un meilleur objet (étage virtuel plus élevé -> raretés boostées)
		var lvl: int = game.floor_num + (4 if force_good else 0)
		var slot: String = Data.SLOTS[game.rng.randi_range(0, Data.SLOTS.size() - 1)]
		var item: Dictionary = Data.generate_item(slot, lvl, game.rng)
		game.loot.append({ "pos": p, "kind": "equip", "glyph": Data.SLOT_GLYPH[slot],
			"sprite": slot, "color": item["rarity_color"], "data": item })

func _pick_artifact_def() -> Dictionary:
	var pool: Array = []
	for def in Data.ARTIFACTS:
		if def["min_floor"] <= game.floor_num and not game.player.has_relic(def["id"]):
			pool.append(def)
	if pool.is_empty():
		return {}
	return pool[game.rng.randi_range(0, pool.size() - 1)]

func _pickup_loot_at(p: Vector2i) -> void:
	for item in game.loot.duplicate():
		if item["pos"] == p:
			game.loot.erase(item)
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
	game.loot.append({ "pos": pos, "kind": "skill", "glyph": "✦", "sprite": "artifact",
		"color": Data.skill_rarity_color(id), "data": { "id": id } })
	game.add_message("[color=#b8a0ff]✦ Une compétence scintille au sol…[/color]")

func _pick_droppable_skill() -> String:
	var pool: Array = []
	var weights: Array = []
	var total: float = 0.0
	for id in Data.SKILLS:
		var s: Dictionary = Data.SKILLS[id]
		if String(s["rarity"]) == "base" or game.known_skills.has(id):
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
	var roll: float = game.rng.randf() * total
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
	if game.known_skills.has(id) or String(Data.SKILLS[id]["rarity"]) == "base":
		game.run_shards += 8
		game.add_message("Compétence déjà connue : %s (+8 Éclats)." % Data.SKILLS[id]["name"])
		return
	game.known_skills.append(id)
	game.add_message("[color=#c8b0ff]✦ Compétence apprise : %s — %s[/color]" % [Data.SKILLS[id]["name"], Data.SKILLS[id]["desc"]])
	game._discover("skill", id, String(Data.SKILLS[id]["name"]))
	game.refresh()

func _bag_add(item: Dictionary) -> void:
	_note_item(item)
	if item.get("unique", false):
		game._discover("unique", String(item.get("name", "")), String(item.get("name", "")))
	if game.inventory.size() >= game.INV_CAP:
		var s: int = int(item.get("salvage", 3))
		game.run_shards += s
		game.add_message("Sac plein : %s recyclé (+%d Éclats)." % [item.get("name", "?"), s])
		return
	game.inventory.append(item)
	var rc: Color = item.get("rarity_color", Color(0.85, 0.85, 0.9))
	game.add_message("Ramassé : [color=#%s]%s[/color].  [I] pour gérer." % [rc.to_html(false), item.get("name", "?")])

## Mémorise l'objet d'équipement le plus rare obtenu du run (journal de fin).
func _note_item(item: Dictionary) -> void:
	if item.get("kind", "") != "equip":
		return
	if game.run_best_item.is_empty() or _rarity_rank(item) > _rarity_rank(game.run_best_item):
		game.run_best_item = item

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
	game.inventory.erase(item)
	var slot: String = item["slot"]
	if game.player.equipment.has(slot):
		var old: Dictionary = game.player.equipment[slot]
		if game.inventory.size() < game.INV_CAP:
			game.inventory.append(old)
		else:
			game.run_shards += int(old.get("salvage", 3))
	game.player.equipment[slot] = item
	game.player.recompute_stats()
	game.add_message("[color=#9fe0ff]Équipé : %s[/color]" % item["name"])
	game.refresh()

func unequip_item(slot: String) -> void:
	if not game.player.equipment.has(slot):
		return
	var it: Dictionary = game.player.equipment[slot]
	game.player.equipment.erase(slot)
	if game.inventory.size() < game.INV_CAP:
		game.inventory.append(it)
	else:
		game.run_shards += int(it.get("salvage", 3))
	game.player.recompute_stats()
	game.add_message("Déséquipé : %s" % it["name"])
	game.refresh()

func salvage_item(item: Dictionary) -> void:
	game.inventory.erase(item)
	var s: int = int(item.get("salvage", 3))
	game.run_shards += s
	game.add_message("Recyclé : %s (+%d Éclats)." % [item.get("name", "?"), s])
	game.refresh()

func use_consumable(item: Dictionary) -> void:
	match item.get("effect", ""):
		"heal_pct":
			var amt: int = int(ceil(game.player.max_hp * float(item["value"])))
			game.player.heal(amt)
			Sfx.play("heal")
			if game.map_view != null:
				game.map_view.fx_damage(game.player.pos(), amt, "heal")
			game.add_message("[color=#7aff8a]%s : +%d PV.[/color]" % [item["name"], amt])
		"heal_full":
			var full_amt: int = game.player.max_hp - game.player.hp
			game.player.heal(game.player.max_hp)
			Sfx.play("heal")
			if game.map_view != null:
				game.map_view.fx_damage(game.player.pos(), full_amt, "heal")
			game.add_message("[color=#7aff8a]%s : PV au maximum ![/color]" % item["name"])
		"shards":
			var s: int = int(item["value"])
			game.run_shards += s
			game.add_message("[color=#ffd24a]%s : +%d Éclats.[/color]" % [item["name"], s])
		"bomb":
			# Phase 6.3 : explose en zone sur l'ennemi visible le plus proche
			# (à défaut, sur la joueuse — auto-dégât possible, c'est une bombe).
			var bt: Entity = game._nearest_enemy_in_range(8)
			var center: Vector2i = bt.pos() if bt != null else game.player.pos()
			var radius: int = int(item.get("radius", 2))
			var boom: int = maxi(4, game.player.atk + game.player.ability_power + game.floor_num)
			Sfx.play("danger")
			game.aoe_attack(center, radius, boom, "%s explose sur" % item["name"])
			game.ignite_area(center, radius)
			game.add_message("[color=#ff8a4a]%s détone (rayon %d) ![/color]" % [item["name"], radius])
		"cure":
			var removed: Array = []
			for st in game.player.statuses.duplicate():
				var sid: String = String(st["id"])
				if sid == "poison" or sid == "burn" or sid == "bleed" or sid == "disease":
					game.player.statuses.erase(st)
					removed.append(sid)
			Sfx.play("heal")
			if removed.is_empty():
				game.add_message("[color=#9fdf9f]%s : rien à purger.[/color]" % item["name"])
			else:
				game.add_message("[color=#9fdf9f]%s purge tes maux (%d).[/color]" % [item["name"], removed.size()])
		"recall":
			var dest: Vector2i = game._random_walkable_near(game.dungeon.stairs, 2) if game.dungeon != null else game.NO_TILE
			if dest == game.NO_TILE:
				game.add_message("[color=#9fb8ff]%s grésille sans effet.[/color]" % item["name"])
			else:
				game.player.x = dest.x
				game.player.y = dest.y
				game.dungeon.reveal(game.player.pos(), game.player.vision)
				if game.map_view != null:
					game.map_view.snap_entity(game.player)
				_pickup_loot_at(game.player.pos())
				game.add_message("[color=#9fb8ff]%s : te voilà près de l'escalier.[/color]" % item["name"])
		"oil_fire":
			game.oil_fire_turns = int(item.get("value", 20))
			game.add_message("[color=#ff9a5a]%s : tes coups brûlent pour %d tours.[/color]" % [item["name"], game.oil_fire_turns])
	game.inventory.erase(item)
	game.refresh()

func _acquire_artifact(def: Dictionary) -> void:
	if game.player.has_relic(def["id"]):
		game.run_shards += 5
		game.add_message("Artefact %s déjà actif (+5 Éclats)." % def["name"])
		return
	game.player.relics.append(game._tag_relic(def, "artifact"))
	game.player.recompute_stats()
	game.add_message("[color=#f0b8ff]✦ Artefact : %s — %s[/color]" % [def["name"], def["desc"]])
	game._discover("relic", String(def["id"]), String(def["name"]))
	game.refresh()

# --- Pouvoirs passifs (Phase 3) ------------------------------------------------
func _drop_power(pos: Vector2i) -> void:
	var def: Dictionary = _pick_power_def()
	if def.is_empty():
		return
	game.loot.append({ "pos": pos, "kind": "power", "glyph": Data.POWER_GLYPH,
		"sprite": "artifact", "color": def["color"], "data": def })
	game.add_message("[color=#ffb84a]Ω Un pouvoir puissant scintille au sol…[/color]")

func _pick_power_def() -> Dictionary:
	var pool: Array = []
	for def in Data.POWERS:
		if not game.player.has_relic(def["id"]):
			pool.append(def)
	if pool.is_empty():
		return {}
	return pool[game.rng.randi_range(0, pool.size() - 1)]

## Renvoie le pouvoir déjà actif qui s'exclut mutuellement avec `def` (vide si aucun).
## N'inspecte que les reliques de tier "power" (les artefacts n'ont pas d'excludes).
func _power_conflict(def: Dictionary) -> Dictionary:
	for ex_id in def.get("excludes", []):
		for p in game.player.relics:
			if p.get("id", "") == ex_id:
				return p
	for p in game.player.relics:
		if p.get("excludes", []).has(def["id"]):
			return p
	return {}

func _acquire_power(def: Dictionary) -> void:
	if game.player.has_relic(def["id"]):
		game.run_shards += 10
		game.add_message("Pouvoir %s déjà actif (+10 Éclats)." % def["name"])
		return
	var conflict: Dictionary = _power_conflict(def)
	if not conflict.is_empty():
		game.run_shards += 10
		game.add_message("[color=#ff8a8a]%s est incompatible avec %s, déjà actif (+10 Éclats).[/color]" % [def["name"], conflict["name"]])
		return
	game.player.relics.append(game._tag_relic(def, "power"))
	game.player.recompute_stats()
	game.add_message("[color=#ffb84a]Ω Pouvoir : %s — %s[/color]" % [def["name"], def["desc"]])
	game._push_timeline("Ω Pouvoir obtenu : %s" % def["name"])
	game._discover("relic", String(def["id"]), String(def["name"]))
	game.refresh()
