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
# Meilleur nombre d'ennemis tués sur un run
var best_kills: int = 0
# Journal du dernier run (affiché au hub après la mort) — non vide après une mort.
var last_run: Dictionary = {}
# Dernier loadout (type d'arme de départ) choisi : "melee" / "ranged" / "magic"
var last_loadout: String = "melee"

func _ready() -> void:
	for key in Data.UPGRADE_ORDER:
		upgrades[key] = 0
	load_game()

func upgrade_level(key: String) -> int:
	return int(upgrades.get(key, 0))

func is_maxed(key: String) -> bool:
	return upgrade_level(key) >= Data.upgrade_max(key)

func can_afford(key: String) -> bool:
	return not is_maxed(key) and shards >= Data.upgrade_cost(key, upgrade_level(key))

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

func bonus_start_shards() -> int:
	return upgrade_level("fortune") * 15

func start_artifacts() -> int:
	return upgrade_level("heritage")

func start_talents() -> int:
	return upgrade_level("instinct")

func add_shards(amount: int) -> void:
	shards += amount

# Enregistre le bilan d'un run terminé (met à jour les records, persiste).
func record_run(stats: Dictionary) -> void:
	last_run = stats
	best_floor = max(best_floor, int(stats.get("floor", 1)))
	best_kills = max(best_kills, int(stats.get("kills", 0)))
	save_game()

# --- Sauvegarde ---------------------------------------------------------------
func save_game() -> void:
	var data := {
		"shards": shards,
		"upgrades": upgrades,
		"best_floor": best_floor,
		"best_kills": best_kills,
		"last_loadout": last_loadout,
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
	best_kills = int(parsed.get("best_kills", 0))
	last_loadout = str(parsed.get("last_loadout", "melee"))
	var saved_up = parsed.get("upgrades", {})
	for key in Data.UPGRADE_ORDER:
		upgrades[key] = int(saved_up.get(key, 0))
