extends RefCounted
## Phase 7.3 (guide d'implémentation) : IA ennemie extraite de Main.gd.
## Module RefCounted détenant une back-reference vers Main (`game`) ; tout
## l'état partagé (player, enemies, rng, dungeon, floor_num...) reste sur
## Main et est lu/écrit via `game.`.

var game: Node2D

func _init(g: Node2D) -> void:
	game = g

## Tour d'un ennemi : applique les traits passifs (rage/berserk, copie, aura,
## piège) puis route vers le comportement data-driven (ai.behavior).
func _enemy_act(e: Entity) -> void:
	# Zone d'agro : un ennemi endormi ignore tout (traits passifs compris) tant
	# qu'il n'a pas été blessé, vu, ou alerté par un cri de meute proche.
	if not e.awake:
		if e.is_boss or String(e.ai.get("behavior", "")) == "stationary":
			e.awake = true
		elif e.hp < e.max_hp:
			e.awake = true                                      # a pris des dégâts
		elif game.dungeon.is_visible(e.x, e.y):
			e.awake = true                                      # vu (réciproque de la vision joueuse)
		elif game._chebyshev(e.pos(), game.player.pos()) <= int(e.ai.get("aggro", 8)):
			e.awake = true
		if e.awake and String(e.ai.get("behavior", "")) != "ambush":
			for o in game.enemies:                              # cri d'alerte aux voisins
				if o.is_alive() and not o.awake and String(o.ai.get("behavior", "")) != "ambush" \
						and game._chebyshev(e.pos(), o.pos()) <= 4:
					o.awake = true
		else:
			return                                              # toujours endormi : tour passé
	if e.ai_cd > 0:
		e.ai_cd -= 1
	# Boss à phases (Dieu-Bête) : ajuste le comportement selon les PV.
	if e.is_boss and e.ai.get("phases", false):
		game._boss_update_phase(e)
	# Rage : Gardien (boss) ET berserkers (ai.berserk), sous un seuil de PV.
	var rage_at: float = 0.8 if game.has_oath("glas") else 0.5
	if (e.is_boss or e.ai.get("berserk", false)) and not e.enraged and e.hp <= e.max_hp * float(e.ai.get("berserk_at", rage_at)):
		e.enraged = true
		e.atk = int(round(e.atk * float(e.ai.get("berserk_mult", 1.4))))
		if e.is_boss:
			game.add_message("[color=#ff4040]⚡ Le Gardien entre en RAGE ! Ses coups redoublent.[/color]")
			if game.map_view != null:
				game.map_view.fx_shake(4.0)
		else:
			game.add_message("[color=#ff6a40]⚡ %s entre en furie berserk ![/color]" % e.display_name)
	# Revenant : copie la puissance offensive de l'héroïne.
	if e.ai.get("copy_player", false):
		e.atk = maxi(e.atk, int(round(game.player.atk * float(e.ai.get("copy_ratio", 0.85)))))
	# Aura de maladie (Zombie) : contamine au contact sans consommer l'action.
	if e.ai.get("disease_aura", false) and game._chebyshev(e.pos(), game.player.pos()) <= 1 and game.player.is_alive():
		game.apply_disease(game.player, 4, maxf(1.0, e.atk * 0.3))
		game.add_message("[color=#9fdf6a]L'aura putride de %s te contamine.[/color]" % e.display_name)
	# Pose de piège (Brigand, Kobold) : à moyenne distance, parfois, au lieu d'agir.
	var pdist: int = game._chebyshev(e.pos(), game.player.pos())
	if e.ai.get("drops_trap", false) and e.ai_cd <= 0 and pdist >= 2 and pdist <= 6 and game.rng.randf() < 0.3:
		game._drop_trap(e.pos())
		e.ai_cd = 5
		return
	match String(e.ai.get("behavior", "melee")):
		"charger": _enemy_act_charger(e)
		"ranged": _enemy_act_ranged(e)
		"caster": _enemy_act_caster(e)
		"fleer": _enemy_act_fleer(e)
		"teleporter": _enemy_act_teleporter(e)
		"ambush": _enemy_act_ambush(e)
		"stationary": pass            # gardiens liés : inertes, à détruire
		_: _enemy_act_melee(e)

## Intention de l'ennemi à afficher (source unique, lue par MapView pour
## télégraphier l'IA) : n'IMPLÉMENTE rien, n'inspecte que les mêmes champs
## que les comportements réels ci-dessus, dans le même ordre de priorité.
func enemy_intent(e: Entity) -> String:
	if String(e.ai.get("behavior", "")) == "ambush" and not e.revealed:
		return ""                      # ne jamais dévoiler un mimic non démasqué
	if not e.awake:
		return "sleep"
	if game._manhattan(e.pos(), game.player.pos()) == 1:
		return "attack"
	var behavior: String = String(e.ai.get("behavior", "melee"))
	if behavior == "charger":
		var dir: Vector2i = Vector2i.ZERO
		if e.x == game.player.x:
			dir = Vector2i(0, signi(game.player.y - e.y))
		elif e.y == game.player.y:
			dir = Vector2i(signi(game.player.x - e.x), 0)
		if dir != Vector2i.ZERO:
			var p: Vector2i = e.pos()
			var steps: int = 0
			while steps < 6:
				var np: Vector2i = p + dir
				if np == game.player.pos():
					return "charge"
				if not game.dungeon.is_walkable(np.x, np.y) or game.enemy_at(np.x, np.y) != null:
					break
				p = np
				steps += 1
	if behavior == "ranged":
		var dist: int = game._chebyshev(e.pos(), game.player.pos())
		if dist <= int(e.ai.get("ranged_range", 5)) and e.ai_cd <= 0 and game.dungeon.has_los(e.pos(), game.player.pos()):
			return "shoot"
	if behavior == "caster":
		var cdist: int = game._chebyshev(e.pos(), game.player.pos())
		if e.ai_cd <= 0 and cdist <= int(e.ai.get("cast_range", 6)):
			return "summon" if String(e.ai.get("cast", "summon")) == "summon" else "cast"
	if behavior == "fleer" and e.hp <= e.max_hp * 0.4:
		return "flee"
	return "approach"

# --- Briques de déplacement réutilisables -------------------------------------
## Avance d'une case vers `target` (axe dominant d'abord). Renvoie true si bougé.
## Boss/élites (ai.smart_path) tentent d'abord un A* (Dungeon.next_step) pour
## contourner de grands obstacles ; repli sur la marche gloutonne si aucun
## chemin n'est trouvé (ou si la case indiquée vient d'être occupée).
func _enemy_step_toward(e: Entity, target: Vector2i) -> bool:
	if e.ai.get("smart_path", false):
		var np: Vector2i = game.dungeon.next_step(e.pos(), target, 400)
		if np != e.pos() and game.enemy_at(np.x, np.y) == null and game.player.pos() != np:
			e.facing = np - e.pos()
			e.x = np.x
			e.y = np.y
			return true
	var dx: int = signi(target.x - e.x)
	var dy: int = signi(target.y - e.y)
	var tries: Array
	if abs(target.x - e.x) >= abs(target.y - e.y):
		tries = [Vector2i(dx, 0), Vector2i(0, dy)]
	else:
		tries = [Vector2i(0, dy), Vector2i(dx, 0)]
	# Évitement minimal d'obstacle : si les deux tentatives directes échouent
	# (mur/arbre/rocher aligné), tente les deux directions perpendiculaires à
	# l'axe dominant, en ordre aléatoire, pour ne pas rester bloquée en ligne droite.
	var perp: Array = [Vector2i(0, 1), Vector2i(0, -1)] if tries[0].y == 0 else [Vector2i(1, 0), Vector2i(-1, 0)]
	if game.rng.randf() < 0.5:
		perp = [perp[1], perp[0]]
	tries.append_array(perp)
	for t in tries:
		if t == Vector2i.ZERO:
			continue
		var np: Vector2i = e.pos() + t
		if game.dungeon.is_walkable(np.x, np.y) and game.enemy_at(np.x, np.y) == null and game.player.pos() != np:
			e.x = np.x; e.y = np.y; e.facing = t
			return true
	return false

## S'éloigne d'une case de `from`. Renvoie true si bougé.
func _enemy_step_away(e: Entity, from: Vector2i) -> bool:
	var dx: int = signi(e.x - from.x)
	var dy: int = signi(e.y - from.y)
	for t in [Vector2i(dx, 0), Vector2i(0, dy), Vector2i(dx, dy)]:
		if t == Vector2i.ZERO:
			continue
		var np: Vector2i = e.pos() + t
		if game.dungeon.is_walkable(np.x, np.y) and game.enemy_at(np.x, np.y) == null and game.player.pos() != np:
			e.x = np.x; e.y = np.y; e.facing = t
			return true
	return false

func _count_allies_near(e: Entity, r: int) -> int:
	var n: int = 0
	for o in game.enemies:
		if o != e and o.is_alive() and game._chebyshev(e.pos(), o.pos()) <= r:
			n += 1
	return n

## Attaque effective d'un ennemi (bonus de meute pour ai.pack).
func _enemy_atk(e: Entity) -> int:
	var a: int = e.atk
	if e.ai.get("pack", false):
		var allies: int = _count_allies_near(e, 2)
		a += int(round(float(e.ai.get("pack_bonus", 2)) * float(mini(allies, 3))))
	if e.has_status("weaken"):
		a -= int(round(e.status_value("weaken")))
	return maxi(1, a)

# --- Comportements ------------------------------------------------------------
func _enemy_act_melee(e: Entity) -> void:
	if game._manhattan(e.pos(), game.player.pos()) == 1:
		game._enemy_attack_player(e)
		return
	_enemy_step_toward(e, game.player.pos())

func _enemy_act_charger(e: Entity) -> void:
	if game._manhattan(e.pos(), game.player.pos()) == 1:
		game._enemy_attack_player(e)
		return
	# Aligné en ligne droite -> charge dévastatrice jusqu'au contact.
	var dir: Vector2i = Vector2i.ZERO
	if e.x == game.player.x:
		dir = Vector2i(0, signi(game.player.y - e.y))
	elif e.y == game.player.y:
		dir = Vector2i(signi(game.player.x - e.x), 0)
	if dir != Vector2i.ZERO:
		var p: Vector2i = e.pos()
		var steps: int = 0
		while steps < 6:
			var np: Vector2i = p + dir
			if np == game.player.pos():
				e.x = p.x; e.y = p.y; e.facing = dir
				var saved: int = e.atk
				e.atk = int(round(e.atk * 1.6))
				game.add_message("[color=#ff9a64]%s charge en trombe ![/color]" % e.display_name)
				game._enemy_attack_player(e)
				e.atk = saved
				# L'impact projette la joueuse (1 case ; 2 pour le Bourreau).
				if game.player.is_alive():
					game.push_entity(game.player, dir, int(e.ai.get("push", 1)))
				return
			if not game.dungeon.is_walkable(np.x, np.y) or game.enemy_at(np.x, np.y) != null:
				break
			p = np
			steps += 1
		if steps > 0:
			e.x = p.x; e.y = p.y; e.facing = dir
			return
	_enemy_step_toward(e, game.player.pos())

func _enemy_act_ranged(e: Entity) -> void:
	if game._manhattan(e.pos(), game.player.pos()) == 1:
		game._enemy_attack_player(e)
		return
	var dist: int = game._chebyshev(e.pos(), game.player.pos())
	# Pas de tir depuis le néant : l'ennemi doit être vu ET avoir la ligne de
	# vue dégagée jusqu'à la joueuse (sinon il approche/kite comme s'il n'avait
	# pas de portée disponible).
	if dist <= int(e.ai.get("ranged_range", 5)) and e.ai_cd <= 0 \
			and game.dungeon.is_visible(e.x, e.y) and game.dungeon.has_los(e.pos(), game.player.pos()):
		_enemy_ranged_attack(e)
		e.ai_cd = int(e.ai.get("cooldown", 1))
		return
	if dist < int(e.ai.get("kite_at", 2)) and _enemy_step_away(e, game.player.pos()):
		return
	_enemy_step_toward(e, game.player.pos())

func _enemy_ranged_attack(e: Entity) -> void:
	game.add_message("[color=#ffb86a]%s t'attaque à distance.[/color]" % e.display_name)
	if game.rng.randf() < game.player.dodge_chance:
		game.add_message("[color=#b3a8e0]Tu esquives le tir de %s ![/color]" % e.display_name)
		return
	game.last_damage_source = e.display_name
	var dealt: int = game.player.take_damage(max(1, _enemy_atk(e) - game._player_def()))
	game.add_message("[color=#ff8a8a]%s te touche (-%d).[/color]" % [e.display_name, dealt])
	game._apply_enemy_on_hit(e)
	game._trigger_armor_retaliation(e, dealt)
	game._check_revive()

func _enemy_act_caster(e: Entity) -> void:
	if e.ai.get("sacrifice", false) and e.hp <= e.max_hp * 0.35:
		_enemy_sacrifice(e)
		return
	var dist: int = game._chebyshev(e.pos(), game.player.pos())
	# Invoquer ne demande pas de visibilité (des renforts qui surgissent de
	# l'obscurité, c'est correct) ; hurler/cibler la joueuse si.
	var needs_los: bool = String(e.ai.get("cast", "summon")) != "summon"
	var can_see: bool = not needs_los or (game.dungeon.is_visible(e.x, e.y) and game.dungeon.has_los(e.pos(), game.player.pos()))
	if e.ai_cd <= 0 and dist <= int(e.ai.get("cast_range", 6)) and can_see:
		_enemy_cast(e)
		e.ai_cd = int(e.ai.get("cooldown", 3))
		return
	if game._manhattan(e.pos(), game.player.pos()) == 1:
		game._enemy_attack_player(e)
		return
	if dist < int(e.ai.get("kite_at", 3)) and _enemy_step_away(e, game.player.pos()):
		return
	_enemy_step_toward(e, game.player.pos())

func _enemy_cast(e: Entity) -> void:
	match String(e.ai.get("cast", "summon")):
		"scream":
			game.add_message("[color=#d9b8ff]%s pousse un cri déchirant ![/color]" % e.display_name)
			game.apply_stun(game.player, int(e.ai.get("stun_turns", 1)))
			game.apply_weaken(game.player, int(e.ai.get("weaken_turns", 4)), float(e.ai.get("weaken_val", 3.0)))
			game.add_message("[color=#cdb8ff]Tu es paralysée et ta défense s'effondre ![/color]")
		_:
			_enemy_summon(e)

func _enemy_summon(e: Entity) -> void:
	if e.spawned_count >= int(e.ai.get("summon_max", 3)):
		_enemy_step_toward(e, game.player.pos())
		return
	var spot: Vector2i = game._free_adjacent(e.pos())
	if spot == game.NO_TILE:
		_enemy_step_toward(e, game.player.pos())
		return
	var def: Dictionary = game._enemy_def_by_sprite(String(e.ai.get("summon", "squelette")))
	if def.is_empty():
		return
	var m: Entity = game._make_enemy(def, game.floor_num, spot)
	m.energy = 0
	m.awake = true
	game.enemies.append(m)
	e.spawned_count += 1
	game.add_message("[color=#c8b0ff]%s invoque un(e) %s ![/color]" % [e.display_name, m.display_name])

func _enemy_sacrifice(e: Entity) -> void:
	game.add_message("[color=#ff6a6a]%s se sacrifie dans une déflagration ![/color]" % e.display_name)
	game.ignite_area(e.pos(), int(e.ai.get("sac_radius", 2)))
	if game._chebyshev(e.pos(), game.player.pos()) <= int(e.ai.get("sac_radius", 2)):
		var dmg: int = maxi(1, int(round(e.atk * float(e.ai.get("sac_mult", 1.6)))) - game._player_def())
		game.last_damage_source = "le sacrifice de %s" % e.display_name
		game.player.take_damage(dmg)
		game.add_message("[color=#ff8a8a]L'explosion te frappe (-%d).[/color]" % dmg)
		game.apply_burn(game.player, 2, maxf(1.0, e.atk * 0.3))
		game._check_revive()
	e.hp = 0
	game.on_enemy_killed(e)

func _enemy_act_fleer(e: Entity) -> void:
	var allies: int = _count_allies_near(e, 3)
	if game._manhattan(e.pos(), game.player.pos()) == 1:
		if (e.hp <= e.max_hp * 0.5 or allies == 0) and _enemy_step_away(e, game.player.pos()):
			return
		game._enemy_attack_player(e)
		return
	if (e.hp <= e.max_hp * 0.4 or allies == 0) and _enemy_step_away(e, game.player.pos()):
		return
	_enemy_step_toward(e, game.player.pos())

func _enemy_act_teleporter(e: Entity) -> void:
	if game._manhattan(e.pos(), game.player.pos()) == 1:
		game._enemy_attack_player(e)
		return
	if game.rng.randf() < float(e.ai.get("teleport_chance", 0.7)):
		var spot: Vector2i = game._random_walkable_near(game.player.pos(), int(e.ai.get("teleport_range", 3)))
		if spot != game.NO_TILE:
			e.x = spot.x
			e.y = spot.y
			return
	_enemy_step_toward(e, game.player.pos())

func _enemy_act_ambush(e: Entity) -> void:
	if not e.revealed:
		if game._chebyshev(e.pos(), game.player.pos()) <= 1:
			e.revealed = true
			e.sprite = "mimic"
			game.add_message("[color=#ff6464]Le coffre était un MIMIC ![/color]")
			var saved: int = e.atk
			e.atk = int(round(e.atk * 1.6))
			game._enemy_attack_player(e)
			e.atk = saved
		return                              # reste immobile et masqué
	if game._manhattan(e.pos(), game.player.pos()) == 1:
		game._enemy_attack_player(e)
		return
	_enemy_step_toward(e, game.player.pos())
