## Une entité sur la grille : héros ou ennemi. Pure donnée (pas de noeud).
class_name Entity
extends RefCounted

enum Faction { PLAYER, ENEMY }

const ACTION_COST := 100        # énergie nécessaire pour agir (système de vitesse)

var display_name: String = "?"
var glyph: String = "?"
var sprite: String = ""
var color: Color = Color.WHITE
var x: int = 0
var y: int = 0
var faction: int = Faction.ENEMY
var is_boss: bool = false
var is_legendary: bool = false    # spawn rare : stats boostées, lâche un pouvoir
var facing: Vector2i = Vector2i(0, 1)   # orientation (sprites directionnels) : bas par défaut
var enraged: bool = false        # boss : passe en rage sous 50% PV (dégâts accrus)
var shard_value: int = 0
var xp_value: int = 0            # XP lâchée à la mort (Phase 5.2 : découplée des Éclats)
# IA / traits d'ENNEMI (data-driven, réutilisable). Vide pour le héros et les
# ennemis simples (comportement "melee" par défaut). Clés possibles : behavior,
# resist_phys, resist_magic, weak_fire, on_hit {id,turns,value}, lifesteal,
# atk_count, summon, summon_max, flee_hp, pack, explode {radius,mult,status},
# disease_aura, teleport, ambush, ranged_range, drops_trap, copy_player...
var ai: Dictionary = {}
var ai_cd: int = 0               # recharge interne d'une capacité d'ennemi
var spawned_count: int = 0       # invocations déjà produites (plafond summon_max)
var revealed: bool = false       # mimic : démasqué une fois le joueur proche
var awake: bool = false          # ennemi : endormi tant qu'il n'a pas été vu/blessé/alerté
var tint: Color = Color.WHITE     # teinte de rendu (élite affixé / Écho) — modulate dans MapView

# --- Stats EFFECTIVES (base + équipement + artefacts + talents) ---
var max_hp: int = 10
var hp: int = 10
var atk: int = 3
var magic: int = 0
var defense: int = 0
var speed: int = 100
var hp_regen: int = 0
# Stats de combat dérivées (héros)
var crit_chance: float = 0.0
var dodge_chance: float = 0.0
var lifesteal_pct: float = 0.0
var thorns_flat: int = 0
var max_revives: int = 0
var revives_used: int = 0
var ability_power: int = 0
var ability_cd_max: int = 0
var vision: int = 4             # rayon de vision (brouillard de guerre)
var procs: Array = []           # Array[{id, value}] issus des objets uniques équipés
var active_synergies: Array = []  # Array[dict Data.SYNERGIES] actives (procs combinés)

# --- Stats de BASE ---
var base_max_hp: int = 10
var base_atk: int = 3
var base_magic: int = 0
var base_defense: int = 0
var base_speed: int = 100
var base_hp_regen: int = 0
var base_ability_power: int = 0
var base_ability_cd: int = 0
var base_vision: int = 4

# --- Sources de modificateurs (héros) ---
var equipment: Dictionary = {}   # slot -> item dict
# Phase 6.4 : artefacts et pouvoirs fusionnés en UNE liste de « reliques ».
# Chaque entrée porte un champ "tier" ("artifact"/"power") pour l'affichage.
var relics: Array = []           # Array[dict] (capacités/pouvoirs passifs)
var talents: Array = []          # Array[dict] (choix de montée de niveau)

# --- Progression de run (héros) ---
var level: int = 1
var xp: int = 0

# --- Capacité active (héros) ---
# active_skill_id : compétence choisie par l'héroïne (Phase 2). ability_id est la
# compétence RÉELLEMENT utilisable (= active_skill_id si compatible avec l'arme,
# sinon repli sur la compétence de base du type équipé). ability_range/cd en dérivent.
var active_skill_id: String = ""
var ability_id: String = ""
var ability_range: int = 1
var ability_cd: int = 0

# --- Système de vitesse ---
var energy: int = 0

# --- Effets de statut (transitoires, durée en TOURS) ---
# Chaque entrée : { id, turns, value, stacks }. DoT : "poison" / "burn"
# (dégâts = value × stacks par tour). "slow" : value = fraction de Vitesse en
# moins. "stun" : saute son tour tant que turns > 0.
var statuses: Array = []

func pos() -> Vector2i:
	return Vector2i(x, y)

func is_alive() -> bool:
	return hp > 0

func is_ready() -> bool:
	return energy >= ACTION_COST

func take_damage(dmg: int) -> int:
	var d: int = max(1, dmg)
	hp = max(0, hp - d)
	return d

func heal(amount: int) -> void:
	if amount <= 0:
		return
	hp = min(max_hp, hp + amount)

func ability_ready() -> bool:
	return ability_cd <= 0

func tick_cooldown() -> void:
	if ability_cd > 0:
		ability_cd -= 1

# --- Effets de statut ---------------------------------------------------------
## Applique/rafraîchit un statut. DoT (poison/burn) cumule jusqu'à max_stacks ;
## les autres (slow/stun) rafraîchissent la durée et gardent la valeur la plus forte.
func add_status(id: String, turns: int, value: float = 0.0, max_stacks: int = 1) -> void:
	for s in statuses:
		if s["id"] == id:
			s["stacks"] = mini(max_stacks, int(s.get("stacks", 1)) + (1 if max_stacks > 1 else 0))
			s["turns"] = maxi(int(s["turns"]), turns)
			s["value"] = maxf(float(s["value"]), value)
			return
	statuses.append({ "id": id, "turns": turns, "value": value, "stacks": 1 })

func has_status(id: String) -> bool:
	for s in statuses:
		if s["id"] == id and int(s["turns"]) > 0:
			return true
	return false

func status_value(id: String) -> float:
	for s in statuses:
		if s["id"] == id:
			return float(s["value"])
	return 0.0

func status_stacks(id: String) -> int:
	for s in statuses:
		if s["id"] == id:
			return int(s.get("stacks", 1))
	return 0

func clear_statuses() -> void:
	statuses.clear()

## Avance les statuts d'un tour : applique les DoT (renvoie les dégâts subis) et
## décrémente toutes les durées, retirant les statuts expirés.
func tick_statuses() -> int:
	var dot: int = 0
	var keep: Array = []
	for s in statuses:
		var id: String = s["id"]
		if id == "poison" or id == "burn" or id == "bleed" or id == "disease":
			dot += int(round(float(s["value"]) * int(s.get("stacks", 1))))
		s["turns"] = int(s["turns"]) - 1
		if int(s["turns"]) > 0:
			keep.append(s)
	statuses = keep
	if dot > 0:
		hp = max(0, hp - dot)
	return dot

## Vitesse effective, réduite par le ralentissement (statut "slow").
func effective_speed() -> int:
	var slow: float = status_value("slow") if has_status("slow") else 0.0
	return maxi(10, int(round(float(speed) * (1.0 - clampf(slow, 0.0, 0.9)))))

## Phase 6.1 : un talent « mécanique » actif ? (repéré par son champ "hook", lu
## aux sites de jeu explicites plutôt que via des +stats plats.)
func has_talent_hook(hook: String) -> bool:
	for t in talents:
		if String(t.get("hook", "")) == hook:
			return true
	return false

## Phase 6.4 : une relique (artefact OU pouvoir) est-elle active ? Les ids sont
## uniques sur l'ensemble fusionné, donc ce test remplace has_artifact/has_power.
func has_relic(id: String) -> bool:
	for r in relics:
		if r.get("id", "") == id:
			return true
	return false

func revive_available() -> bool:
	return revives_used < max_revives

func has_proc(id: String) -> bool:
	for p in procs:
		if p["id"] == id:
			return true
	return false

func proc_value(id: String) -> float:
	for p in procs:
		if p["id"] == id:
			return float(p["value"])
	return 0.0

## Recalcule toutes les stats effectives à partir de la base et des sources.
func recompute_stats() -> void:
	max_hp = base_max_hp
	atk = base_atk
	magic = base_magic
	defense = base_defense
	speed = base_speed
	hp_regen = base_hp_regen
	ability_power = base_ability_power
	vision = base_vision
	# Compétence active = celle choisie, si compatible avec l'arme équipée ;
	# sinon repli automatique sur la compétence de base du type d'arme.
	ability_id = ""
	ability_range = 1
	var weapon_cd: int = 0
	var wtype: String = String(equipment.get("arme", {}).get("weapon_type", ""))
	if wtype != "":
		var sid: String = active_skill_id
		if sid == "" or String(Data.SKILLS.get(sid, {}).get("wtype", "")) != wtype:
			sid = String(Data.WEAPON_TYPE_BASE_SKILL.get(wtype, ""))
		active_skill_id = sid
		if sid != "" and Data.SKILLS.has(sid):
			ability_id = sid
			ability_range = int(Data.SKILLS[sid]["range"])
			weapon_cd = int(Data.SKILLS[sid]["cd"])
	ability_cd_max = base_ability_cd + weapon_cd
	crit_chance = 0.0
	dodge_chance = 0.0
	lifesteal_pct = 0.0
	thorns_flat = 0
	max_revives = 0
	procs = []
	for slot in equipment:
		var it: Dictionary = equipment[slot]
		_apply_mods(it.get("bonus", {}))
		if it.get("proc", "") != "":
			procs.append({ "id": it["proc"], "value": it.get("proc_val", 0.0) })
	for t in talents:
		_apply_mods(t.get("mods", {}))
	# Phase 6.4 : reliques unifiées (artefacts + pouvoirs) via Data.RELIC_MODS.
	# Les artefacts n'ont pas de clés atk_pct/max_hp_pct → += 0, sans effet.
	var atk_pct: float = 0.0
	var max_hp_pct: float = 0.0
	for r in relics:
		var rm: Dictionary = Data.RELIC_MODS.get(r.get("id", ""), {})
		_apply_mods(rm)
		atk_pct += float(rm.get("atk_pct", 0.0))
		max_hp_pct += float(rm.get("max_hp_pct", 0.0))
	if atk_pct != 0.0:
		atk = int(round(atk * (1.0 + atk_pct)))
	if max_hp_pct != 0.0:
		max_hp = int(round(max_hp * (1.0 + max_hp_pct)))
	_detect_synergies()
	speed = max(20, speed)
	ability_cd_max = max(0, ability_cd_max)
	vision = max(1, vision)
	dodge_chance = minf(dodge_chance, Data.CAP_DODGE)
	crit_chance = minf(crit_chance, Data.CAP_CRIT)
	lifesteal_pct = minf(lifesteal_pct, Data.CAP_LIFESTEAL)
	hp = min(hp, max_hp)

## Active les synergies dont TOUS les procs requis sont équipés, et amplifie la
## valeur des procs concernés. À appeler une fois les procs assemblés.
func _detect_synergies() -> void:
	active_synergies = []
	for syn in Data.SYNERGIES:
		var all_present := true
		for pid in syn["requires"]:
			if not has_proc(pid):
				all_present = false
				break
		if not all_present:
			continue
		active_synergies.append(syn)
		var factor: float = 1.0 + float(syn["boost"])
		for p in procs:
			if syn["requires"].has(p["id"]):
				p["value"] = float(p["value"]) * factor

func _apply_mods(m: Dictionary) -> void:
	max_hp += int(m.get("max_hp", 0))
	atk += int(m.get("atk", 0))
	magic += int(m.get("magic", 0))
	defense += int(m.get("defense", 0))
	speed += int(m.get("speed", 0))
	hp_regen += int(m.get("hp_regen", 0))
	ability_power += int(m.get("ability_power", 0))
	ability_cd_max += int(m.get("ability_cd", 0))
	vision += int(m.get("vision", 0))
	crit_chance += float(m.get("crit_chance", 0.0))
	dodge_chance += float(m.get("dodge_chance", 0.0))
	lifesteal_pct += float(m.get("lifesteal_pct", 0.0))
	thorns_flat += int(m.get("thorns_flat", 0))
	max_revives += int(m.get("max_revives", 0))
