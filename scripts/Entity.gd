## Une entité sur la grille : héros ou ennemi. Pure donnée (pas de noeud).
class_name Entity
extends RefCounted

enum Faction { PLAYER, ENEMY }

var display_name: String = "?"
var glyph: String = "?"
var color: Color = Color.WHITE
var x: int = 0
var y: int = 0
var max_hp: int = 10
var hp: int = 10
var atk: int = 3
var faction: int = Faction.ENEMY
var is_boss: bool = false
var shard_value: int = 0

# Capacité (héros uniquement)
var ability_id: String = ""
var ability_range: int = 1
var ability_cd_max: int = 0
var ability_cd: int = 0          # compte à rebours courant (0 = prêt)
var ability_power: int = 0       # bonus de puissance issu de la méta

func pos() -> Vector2i:
	return Vector2i(x, y)

func is_alive() -> bool:
	return hp > 0

func take_damage(dmg: int) -> int:
	var d: int = max(1, dmg)
	hp = max(0, hp - d)
	return d

func heal(amount: int) -> void:
	hp = min(max_hp, hp + amount)

func ability_ready() -> bool:
	return ability_cd <= 0

func tick_cooldown() -> void:
	if ability_cd > 0:
		ability_cd -= 1
