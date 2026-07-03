extends RefCounted
## Phase 7.3 (guide d'implémentation) : système de combat extrait de Main.gd.
## Module RefCounted détenant une back-reference vers Main (`game`) ; tout
## l'état partagé (player, enemies, rng, dungeon, floor_num...) reste sur
## Main et est lu/écrit via `game.`.

var game: Node2D

func _init(g: Node2D) -> void:
	game = g

# --- Primitives de combat (briques réutilisées par les compétences/pouvoirs) --
## Zone : frappe tous les ennemis vivants dans le rayon (Chebyshev) du centre.
func aoe_attack(center: Vector2i, radius: int, base: int, verb: String) -> int:
	var hits := 0
	for e in game.enemies.duplicate():
		if not e.is_alive() or game._chebyshev(center, e.pos()) > radius:
			continue
		# À bout portant (rayon 1), les murs n'arrêtent pas le souffle ; au-delà,
		# la ligne de vue doit être dégagée.
		if radius >= 2 and not game.dungeon.has_los(center, e.pos()):
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
		if not game.dungeon.is_walkable(p.x, p.y):
			break
		var e: Entity = game.enemy_at(p.x, p.y)
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
		current = game._nearest_enemy_excluding(current.pos(), jump_range, hit_ids)
	return hits

## Dash : déplace le joueur de `distance` cases dans `dir`, s'arrêtant avant un
## obstacle ou un ennemi. Renvoie le nombre de cases parcourues.
func dash(dir: Vector2i, distance: int) -> int:
	var moved := 0
	for i in distance:
		var nx: int = game.player.x + dir.x
		var ny: int = game.player.y + dir.y
		if not game.dungeon.is_walkable(nx, ny) or game.enemy_at(nx, ny) != null or Vector2i(nx, ny) == game.dungeon.stairs:
			break
		game.player.x = nx
		game.player.y = ny
		moved += 1
	if moved > 0:
		game._pickup_loot_at(game.player.pos())
	return moved

## Projection (Phase 4.3) : pousse `target` (joueuse ou ennemi) de `tiles`
## cases dans `dir`. Chaque case rencontrée applique sa règle : entité →
## collision (2 dégâts chacun, stop) ; lave (volcan) → brûlure sévère, la
## cible est repoussée sur sa case d'origine ; eau → 3 dégâts + ralenti, stop
## au bord ; glace → glisse (1 case bonus) ; piège → se déclenche contre la
## cible poussée ; mur/arbre/rocher → stop net.
func push_entity(target: Entity, dir: Vector2i, tiles: int, by_player: bool = false) -> void:
	if dir == Vector2i.ZERO or target == null or not target.is_alive() or game.dungeon == null:
		return
	# Talent Démolisseur (Phase 6.1) : les poussées de la joueuse gagnent +1 case
	# et +3 dégâts environnementaux/de collision contre l'entité poussée.
	var demo: bool = by_player and game.player != null and game.player.has_talent_hook("demolisseur")
	var push_bonus: int = 3 if demo else 0
	var remaining: int = tiles + (1 if demo else 0)
	var slid: bool = false
	while remaining > 0:
		remaining -= 1
		var next: Vector2i = target.pos() + dir
		if next.x <= 0 or next.x >= game.dungeon.width - 1 or next.y <= 0 or next.y >= game.dungeon.height - 1:
			break
		var occupant: Entity = game._entity_at(next)
		if occupant != null and occupant != target:
			# Collision : les deux encaissent.
			if target == game.player:
				game.last_damage_source = "une collision avec %s" % occupant.display_name
			target.take_damage(2)
			occupant.take_damage(2 + push_bonus)
			game.add_message("[color=#ffb86a]Collision : %s et %s encaissent (-2 chacun).[/color]" %
				["toi" if target == game.player else target.display_name,
				 "toi" if occupant == game.player else occupant.display_name])
			if occupant != game.player and not occupant.is_alive():
				game.on_enemy_killed(occupant)
			break
		if game.dungeon.tiles[next.y][next.x] == Dungeon.WATER and game.dungeon.effects[next.y][next.x] != Dungeon.EFF_FROZEN:
			if game.dungeon.is_lava():
				# Lave : morsure ardente, la cible rebondit sur sa case d'origine.
				if target == game.player:
					game.last_damage_source = "la lave"
				target.take_damage(8 + game.floor_num + push_bonus)
				apply_burn(target, 3, 3.0)
				game.add_message("[color=#ff8a4a]La lave mord %s ![/color]" %
					("ta chair" if target == game.player else target.display_name))
			else:
				# Eau : reste sur la dernière case valide, trempé et ralenti.
				if target == game.player:
					game.last_damage_source = "l'eau glacée"
				target.take_damage(3 + push_bonus)
				apply_slow(target, 2, 0.4)
				game.add_message("[color=#9fdfff]%s au bord de l'eau, trempé et ralenti.[/color]" %
					("Tu vacilles" if target == game.player else "%s vacille" % target.display_name))
			break
		if not game.dungeon.is_walkable(next.x, next.y):
			break                              # mur / arbre / rocher : stop net
		target.x = next.x
		target.y = next.y
		if game.dungeon.effects[next.y][next.x] == Dungeon.EFF_FROZEN and not slid:
			slid = true
			remaining += 1                     # glace : glisse une case de plus
		game._trigger_hazard_at(target.pos(), target)   # les pièges coupent enfin dans les deux sens
		if not target.is_alive():
			break
	if target == game.player:
		_check_revive()
		if game.player.is_alive():
			game._pickup_loot_at(game.player.pos())
	elif not target.is_alive():
		game.on_enemy_killed(target)

# --- Statuts : application (utilisés par compétences/pouvoirs) -----------------
func apply_poison(target: Entity, turns: int, dmg_per_turn: float, max_stacks: int = 10) -> void:
	var v: float = dmg_per_turn
	# Talent Toxicologue (Phase 6.1) : ×1.6 sur les poisons que la joueuse inflige
	# aux ennemis (les statuts ne tracent pas leur applicant — v1 honnête : on
	# gate sur « cible ennemie » pour ne jamais amplifier un poison subi).
	if target.faction == Entity.Faction.ENEMY and game.player != null and game.player.has_talent_hook("toxicologue"):
		v *= 1.6
	target.add_status("poison", turns, v, max_stacks)

func apply_burn(target: Entity, turns: int, dmg_per_turn: float, max_stacks: int = 5) -> void:
	if not target.ai.is_empty() and target.ai.get("immune_fire", false):
		return                                   # Élémentaire de feu : insensible au feu
	# Talent Pyromane (Phase 6.1) : +1 palier de brûlure max sur les cibles ennemies.
	if target.faction == Entity.Faction.ENEMY and game.player != null and game.player.has_talent_hook("pyromane"):
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

func _player_attack(target: Entity, base_raw: int, verb: String, ignore_def: bool = false) -> void:
	var raw: float = float(base_raw)
	# Résistances de l'ennemi (data-driven via ai.resist_phys / resist_magic ;
	# une valeur négative = vulnérabilité, ex. le Golem face aux sorts).
	if not target.ai.is_empty():
		var resist: float = float(target.ai.get("resist_magic", 0.0)) if game._attack_dmg_type == "magic" else float(target.ai.get("resist_phys", 0.0))
		if resist != 0.0:
			raw *= clampf(1.0 - resist, 0.05, 2.5)
	# Boss protégé par ses gardiens (âmes-boucliers / chaudrons) tant qu'ils vivent.
	if target.is_boss and target.ai.has("guardians") and game._living_guardians(target) > 0:
		raw *= clampf(1.0 - float(target.ai["guardians"].get("resist", 0.85)), 0.02, 1.0)
		if game.rng.randf() < 0.34:
			game.add_message("[color=#9fb8ff]%s est protégé — détruis ses gardiens ![/color]" % target.display_name)
	# Talents mécaniques (Phase 6.1) :
	# Berserker — +25% de dégâts tant que la joueuse subit un DoT.
	if game.player.has_talent_hook("berserker") and game._player_has_dot():
		raw *= 1.25
	# Chasseur nocturne — +10% de dégâts à distance ≥ 4 (saveur « tir à distance »).
	if game.player.has_talent_hook("chasseur_nuit") and game._chebyshev(game.player.pos(), target.pos()) >= 4:
		raw *= 1.10
	var is_execute := false
	if game.player.has_proc("frenesie") and game.player.hp <= game.player.max_hp * 0.4:
		raw *= 1.0 + game.player.proc_value("frenesie")
	if game.player.has_proc("execution") and target.hp <= target.max_hp * 0.25:
		raw *= 1.0 + game.player.proc_value("execution")
		is_execute = true
	var force_crit: bool = game.player.has_proc("premier_coup") and not game.first_strike_used
	game.first_strike_used = true
	var crit: bool = force_crit or game.rng.randf() < game.player.crit_chance
	if crit:
		raw *= 2.0
	var def: int = 0 if ignore_def else target.defense
	if game.map_view != null:
		game.map_view.fx_attack(game.player, target.pos())
		game.map_view.fx_hit(target)
	Sfx.play("crit" if crit else "hit")
	var dealt: int = target.take_damage(max(1, int(round(raw)) - def))
	game.run_best_hit = max(game.run_best_hit, dealt)
	if game.map_view != null:
		game.map_view.fx_damage(target.pos(), dealt, "crit" if crit else "hit")
		if crit:
			game.map_view.fx_freeze(0.05)
			game.map_view.fx_shake(4.0)
	# Araignée Mère : pond une créature à chaque coup reçu (jusqu'à un quota).
	if target.is_boss and target.ai.has("spawn_on_hit") and target.is_alive() and target.spawned_count < int(target.ai.get("soh_max", 6)):
		var ssp: Vector2i = game._free_adjacent(target.pos())
		if ssp != game.NO_TILE:
			var smdef: Dictionary = game._enemy_def_by_sprite(String(target.ai["spawn_on_hit"]))
			if not smdef.is_empty():
				var sm: Entity = game._make_enemy(smdef, game.floor_num, ssp)
				sm.energy = 0
				sm.awake = true
				game.enemies.append(sm)
				target.spawned_count += 1
				game.add_message("[color=#9fdf6a]%s pond une créature ![/color]" % target.display_name)
	var flair := ""
	if force_crit:
		flair = "  [color=#ffd24a]COUP MORTEL![/color]"
	elif is_execute:
		flair = "  [color=#c0303a]EXÉCUTION![/color]"
	elif crit:
		flair = "  [color=#ffec5a]CRITIQUE![/color]"
	game.add_message("%s %s (-%d)%s" % [verb, target.display_name, dealt, flair])
	if game.player.has_relic("venin") and target.is_alive():
		apply_poison(target, 3, maxf(1.0, round(float(dealt) * 0.25)))
	# Huile ardente (Phase 6.3) : brûlure au contact tant que le buff est actif.
	if game.oil_fire_turns > 0 and target.is_alive():
		apply_burn(target, 2, maxf(1.0, 2.0 + game.floor_num * 0.2))
	if game.player.lifesteal_pct > 0.0 and dealt > 0:
		var healed: int = int(ceil(dealt * game.player.lifesteal_pct))
		if healed > 0:
			game.player.heal(healed)
			if game.map_view != null:
				game.map_view.fx_damage(game.player.pos(), healed, "heal")
			game.add_message("[color=#ff7a8a]Vol de vie : +%d PV.[/color]" % healed)
	_trigger_weapon_prefixes(target)
	game._elemental_reaction(target.pos(), dealt)
	if not target.is_alive():
		game.on_enemy_killed(target)
		return
	if game.player.has_proc("frappe_double") and game.rng.randf() < game.player.proc_value("frappe_double"):
		var raw2: int = int(round(base_raw * 0.5))
		var dealt2: int = target.take_damage(max(1, raw2 - target.defense))
		game.run_best_hit = max(game.run_best_hit, dealt2)
		game.add_message("[color=#ffb86a]Frappe double sur %s (-%d).[/color]" % [target.display_name, dealt2])
		if game.player.lifesteal_pct > 0.0 and dealt2 > 0:
			var healed2: int = int(ceil(dealt2 * game.player.lifesteal_pct))
			game.player.heal(healed2)
			if game.map_view != null:
				game.map_view.fx_damage(game.player.pos(), healed2, "heal")
		if not target.is_alive():
			game.on_enemy_killed(target)

## Déclenche les préfixes de combat de l'ARME équipée (façon Dungeonmans),
## indépendants des procs d'objets uniques : dégâts de feu bonus ("ardent"),
## puis chances de ralentir/empoisonner/étourdir la cible touchée. N'agit
## que sur le coup principal (pas sur la Frappe Double), comme le Venin/Vol
## de vie déjà présents.
func _trigger_weapon_prefixes(target: Entity) -> void:
	if game.player.has_proc("ardent") and target.is_alive():
		var fdmg: int = _fire_prefix_damage(target, game.player.proc_value("ardent"))
		if fdmg > 0:
			var extra: int = target.take_damage(fdmg)
			game.run_best_hit = max(game.run_best_hit, extra)
			if game.map_view != null:
				game.map_view.fx_damage(target.pos(), extra, "hit")
			game.add_message("[color=#ff9a5a]Brasier : %s subit -%d (feu).[/color]" % [target.display_name, extra])
		if game.rng.randf() < 0.25:   # (tune) chance d'embraser un arbre adjacent à la cible
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if game.ignite(target.pos() + d):
					break
	if not target.is_alive():
		return
	if game.player.has_proc("givre") and game.rng.randf() < game.player.proc_value("givre"):
		apply_slow(target, 2, 0.35)
		game.add_message("[color=#9fdfff]%s est ralenti par le givre.[/color]" % target.display_name)
		game.freeze_water_near(target.pos())   # élément givre : l'eau au contact gèle
	if game.player.has_proc("venimeux") and game.rng.randf() < game.player.proc_value("venimeux"):
		apply_poison(target, 3, 3.0)
		game.add_message("[color=#9fdf6a]%s est empoisonné par le venin.[/color]" % target.display_name)
	if game.player.has_proc("foudroyant") and game.rng.randf() < game.player.proc_value("foudroyant"):
		apply_stun(target, 1)
		game.add_message("[color=#cdb8ff]%s est étourdi par la foudre ![/color]" % target.display_name)

## Dégâts de feu instantanés bonus (préfixe "ardent") : respecte l'immunité et
## la faiblesse au feu des ennemis (mêmes règles que apply_burn).
func _fire_prefix_damage(target: Entity, avg: float) -> int:
	if avg <= 0.0 or (not target.ai.is_empty() and target.ai.get("immune_fire", false)):
		return 0
	var v: float = avg + game.rng.randf_range(-1.0, 1.0)
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
		if not attacker.is_alive() or not game.player.is_alive():
			return
		if _enemy_hit_player(attacker):
			connected = true
	# Le statut au contact ne s'applique qu'une fois par séquence d'attaque,
	# et seulement si au moins un coup a réellement porté (pas d'esquive totale).
	if connected:
		game._apply_enemy_on_hit(attacker)

## Un coup unique d'ennemi vers le joueur. Renvoie true si le coup a porté.
func _enemy_hit_player(attacker: Entity) -> bool:
	if game.rng.randf() < game.player.dodge_chance:
		game.add_message("[color=#b3a8e0]Tu esquives %s ![/color]" % attacker.display_name)
		return false
	if game.map_view != null:
		game.map_view.fx_attack(attacker, game.player.pos())
		game.map_view.fx_hit(game.player)
	game.last_damage_source = attacker.display_name
	var dealt: int = game.player.take_damage(max(1, game._enemy_atk(attacker) - game._player_def()))
	if game.map_view != null:
		game.map_view.fx_damage(game.player.pos(), dealt, "player_hit")
	game.add_message("[color=#ff8a8a]%s te frappe (-%d).[/color]" % [attacker.display_name, dealt])
	var ls: float = float(attacker.ai.get("lifesteal", 0.0))
	if ls > 0.0 and dealt > 0:
		var drained: int = maxi(1, int(round(dealt * ls)))
		attacker.heal(drained)
		game.add_message("[color=#ff7a8a]%s te draine (+%d PV).[/color]" % [attacker.display_name, drained])
	# Élite « Voleur » (Phase 6.2) : dérobe des Éclats à chaque coup (rendus à sa mort).
	var steal: int = int(attacker.ai.get("steal", 0))
	if steal > 0 and dealt > 0:
		var taken: int = mini(steal, game.run_shards)
		if taken > 0:
			game.run_shards -= taken
			attacker.ai["stolen"] = int(attacker.ai.get("stolen", 0)) + taken
			game.add_message("[color=#ffd24a]%s te dérobe %d Éclats ![/color]" % [attacker.display_name, taken])
	if game.player.thorns_flat > 0:
		var d2: int = attacker.take_damage(game.player.thorns_flat)
		game.add_message("[color=#cdd66a]Épines : %s subit %d.[/color]" % [attacker.display_name, d2])
		if not attacker.is_alive():
			game.on_enemy_killed(attacker)
	game._trigger_armor_retaliation(attacker, dealt)
	_check_revive()
	return true

func _check_revive() -> void:
	if game.player.hp <= 0 and game.player.revive_available():
		game.player.revives_used += 1
		game.player.hp = max(1, int(game.player.max_hp * 0.5))
		game.add_message("[color=#ffd24a]✦ Une résurrection te ramène à la vie (50% PV) ![/color]")
