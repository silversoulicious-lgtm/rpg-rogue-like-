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
var shard_value: int = 0

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

# --- Stats de BASE ---
var base_max_hp: int = 10
var base_atk: int = 3
var base_magic: int = 0
var base_defense: int = 0
var base_speed: int = 100
var base_hp_regen: int = 0
var base_ability_power: int = 0
var base_ability_cd: int = 0

# --- Sources de modificateurs (héros) ---
var equipment: Dictionary = {}   # slot -> item dict
var artifacts: Array = []        # Array[dict] (capacités passives)
var talents: Array = []          # Array[dict] (choix de montée de niveau)

# --- Progression de run (héros) ---
var level: int = 1
var xp: int = 0

# --- Capacité active (héros) ---
var ability_id: String = ""
var ability_range: int = 1
var ability_cd: int = 0

# --- Système de vitesse ---
var energy: int = 0

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

func has_artifact(id: String) -> bool:
	for a in artifacts:
		if a.get("id", "") == id:
			return true
	return false

func revive_available() -> bool:
	return revives_used < max_revives

## Recalcule toutes les stats effectives à partir de la base et des sources.
func recompute_stats() -> void:
	max_hp = base_max_hp
	atk = base_atk
	magic = base_magic
	defense = base_defense
	speed = base_speed
	hp_regen = base_hp_regen
	ability_power = base_ability_power
	ability_cd_max = base_ability_cd
	crit_chance = 0.0
	dodge_chance = 0.0
	lifesteal_pct = 0.0
	thorns_flat = 0
	max_revives = 0
	for slot in equipment:
		_apply_mods(equipment[slot].get("bonus", {}))
	for a in artifacts:
		_apply_mods(Data.ARTIFACT_MODS.get(a.get("id", ""), {}))
	for t in talents:
		_apply_mods(t.get("mods", {}))
	speed = max(20, speed)
	ability_cd_max = max(0, ability_cd_max)
	hp = min(hp, max_hp)

func _apply_mods(m: Dictionary) -> void:
	max_hp += int(m.get("max_hp", 0))
	atk += int(m.get("atk", 0))
	magic += int(m.get("magic", 0))
	defense += int(m.get("defense", 0))
	speed += int(m.get("speed", 0))
	hp_regen += int(m.get("hp_regen", 0))
	ability_power += int(m.get("ability_power", 0))
	ability_cd_max += int(m.get("ability_cd", 0))
	crit_chance += float(m.get("crit_chance", 0.0))
	dodge_chance += float(m.get("dodge_chance", 0.0))
	lifesteal_pct += float(m.get("lifesteal_pct", 0.0))
	thorns_flat += int(m.get("thorns_flat", 0))
	max_revives += int(m.get("max_revives", 0))
