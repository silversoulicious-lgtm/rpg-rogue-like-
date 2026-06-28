## Singleton (autoload) : méta-progression PERSISTANTE entre les runs.
## C'est le cœur de la boucle "à la mort, on améliore ses capacités selon le butin".
extends Node

const SAVE_PATH := "user://save.json"

# Banque d'Éclats récoltés (monnaie méta dépensée pour les améliorations)
var shards: int = 0
# Niveaux d'amélioration achetés : { "vitalite": int, "force": int, "maitrise": int }
var upgrades: Dictionary = {}
# Meilleur étage atteint (record du joueur)
var best_floor: int = 1
# Dernier héros choisi
var last_hero: String = "knight"

func _ready() -> void:
	for key in Data.UPGRADE_ORDER:
		upgrades[key] = 0
	load_game()

func upgrade_level(key: String) -> int:
	return int(upgrades.get(key, 0))

func can_afford(key: String) -> bool:
	return shards >= Data.upgrade_cost(key, upgrade_level(key))

func buy_upgrade(key: String) -> bool:
	if not can_afford(key):
		return false
	shards -= Data.upgrade_cost(key, upgrade_level(key))
	upgrades[key] = upgrade_level(key) + 1
	save_game()
	return true

# Bonus dérivés des améliorations, appliqués au début de chaque run.
func bonus_hp() -> int:
	return upgrade_level("vitalite") * 5

func bonus_atk() -> int:
	return upgrade_level("force") * 1

func bonus_ability_power() -> int:
	return upgrade_level("maitrise") * 2

func add_shards(amount: int) -> void:
	shards += amount

func record_floor(floor: int) -> void:
	best_floor = max(best_floor, floor)
	save_game()

# --- Sauvegarde ---------------------------------------------------------------
func save_game() -> void:
	var data := {
		"shards": shards,
		"upgrades": upgrades,
		"best_floor": best_floor,
		"last_hero": last_hero,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	shards = int(parsed.get("shards", 0))
	best_floor = int(parsed.get("best_floor", 1))
	last_hero = str(parsed.get("last_hero", "knight"))
	var saved_up = parsed.get("upgrades", {})
	for key in Data.UPGRADE_ORDER:
		upgrades[key] = int(saved_up.get(key, 0))
