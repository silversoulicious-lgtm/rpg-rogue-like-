## Une entité sur la grille : héros ou ennemi. Pure donnée (pas de noeud).
class_name Entity
extends RefCounted

enum Faction { PLAYER, ENEMY }

const ACTION_COST := 100        # énergie nécessaire pour agir (système de vitesse)

var display_name: String = "?"
var glyph: String = "?"
var color: Color = Color.WHITE
var x: int = 0
var y: int = 0
var faction: int = Faction.ENEMY
var is_boss: bool = false
var shard_value: int = 0

# --- Stats EFFECTIVES (base + équipement) ---
var max_hp: int = 10
var hp: int = 10
var atk: int = 3            # attaque physique
var magic: int = 0         # puissance magique (booste les capacités)
var defense: int = 0       # réduction de dégâts à plat
var speed: int = 100       # énergie gagnée par tick (100 = normal)
var hp_regen: int = 0      # PV régénérés à chaque action

# --- Stats de BASE (pour recalculer après équipement, héros surtout) ---
var base_max_hp: int = 10
var base_atk: int = 3
var base_magic: int = 0
var base_defense: int = 0
var base_speed: int = 100
var base_hp_regen: int = 0

# --- Équipement & artefacts (héros) ---
var equipment: Dictionary = {}   # slot -> item dict
var artifacts: Array = []        # Array[dict] (capacités passives)
var revive_used: bool = false    # Plume de Phénix consommée ?

# --- Capacité active (héros) ---
var ability_id: String = ""
var ability_range: int = 1
var ability_cd_max: int = 0
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

## Recalcule les stats effectives du héros à partir de la base + équipement.
func recompute_stats() -> void:
	max_hp = base_max_hp
	atk = base_atk
	magic = base_magic
	defense = base_defense
	speed = base_speed
	hp_regen = base_hp_regen
	for slot in equipment:
		var item: Dictionary = equipment[slot]
		var b: Dictionary = item.get("bonus", {})
		max_hp += int(b.get("max_hp", 0))
		atk += int(b.get("atk", 0))
		magic += int(b.get("magic", 0))
		defense += int(b.get("defense", 0))
		speed += int(b.get("speed", 0))
		hp_regen += int(b.get("hp_regen", 0))
	# Artefacts qui octroient des stats passives.
	for a in artifacts:
		var ab: Dictionary = a.get("bonus", {})
		max_hp += int(ab.get("max_hp", 0))
		atk += int(ab.get("atk", 0))
		magic += int(ab.get("magic", 0))
		defense += int(ab.get("defense", 0))
		speed += int(ab.get("speed", 0))
		hp_regen += int(ab.get("hp_regen", 0))
	speed = max(20, speed)            # garde-fou (évite une vitesse nulle/négative)
	hp = min(hp, max_hp)
