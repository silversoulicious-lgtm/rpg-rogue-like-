## Singleton (autoload) : méta-progression PERSISTANTE entre les runs.
## C'est le cœur de la boucle "à la mort, on améliore ses capacités selon le butin".
extends Node

const SAVE_PATH := "user://save.json"

# Banque d'Éclats récoltés (monnaie méta dépensée pour les améliorations)
var shards: int = 0
# Banque de Connaissances (2ᵉ monnaie méta : débloque des systèmes via l'Arbre)
var knowledge: int = 0
# Nœuds de l'Arbre de Connaissances déjà débloqués (ids de Data.KNOWLEDGE_NODES)
var knowledge_nodes: Array = []
# Codex : éléments déjà rencontrés, par catégorie -> { id/nom: true }
var discovered: Dictionary = { "skill": {}, "power": {}, "unique": {} }
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
# Réglages persistants (volumes, tremblement d'écran) — écran Options.
var settings: Dictionary = { "sfx_vol": 0.8, "music_vol": 0.8, "screenshake": true }

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

# --- Arbre de Connaissances ---------------------------------------------------
func add_knowledge(amount: int) -> void:
	knowledge += amount

func has_knowledge_node(id: String) -> bool:
	return knowledge_nodes.has(id)

## Tous les prérequis d'un nœud sont-ils débloqués ?
func node_prereqs_met(id: String) -> bool:
	for req in Data.KNOWLEDGE_NODES.get(id, {}).get("requires", []):
		if not has_knowledge_node(req):
			return false
	return true

func can_unlock_node(id: String) -> bool:
	if has_knowledge_node(id) or not Data.KNOWLEDGE_NODES.has(id):
		return false
	return node_prereqs_met(id) and knowledge >= int(Data.KNOWLEDGE_NODES[id]["cost"])

func buy_knowledge_node(id: String) -> bool:
	if not can_unlock_node(id):
		return false
	knowledge -= int(Data.KNOWLEDGE_NODES[id]["cost"])
	knowledge_nodes.append(id)
	save_game()
	return true

# Raccourcis de lecture des déblocages (utilisés par la logique de run).
func starts_with_power() -> bool:    return has_knowledge_node("pacte_pouvoir")
func better_drop_pool() -> bool:     return has_knowledge_node("affinite")
func shop_always_power() -> bool:    return has_knowledge_node("arsenal")
func oaths_unlocked() -> bool:       return has_knowledge_node("serments")
func major_oaths_unlocked() -> bool: return has_knowledge_node("serment_majeur")
func legendary_boost() -> bool:      return has_knowledge_node("chasseur")
func codex_unlocked() -> bool:       return has_knowledge_node("codex")
func reveals_loot() -> bool:         return has_knowledge_node("oeil_du_devin")
func forge_unlocked() -> bool:       return has_knowledge_node("forge")

## Enregistre une rencontre dans le Codex. Renvoie true si c'est une PREMIÈRE
## (le Codex doit être débloqué pour que la collection se remplisse et rapporte).
func note_discovery(category: String, key: String) -> bool:
	if not codex_unlocked() or key == "":
		return false
	var bucket: Dictionary = discovered.get(category, {})
	if bucket.has(key):
		return false
	bucket[key] = true
	discovered[category] = bucket
	knowledge += 1
	save_game()
	return true

func discovered_count(category: String) -> int:
	return int(discovered.get(category, {}).size())

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
		"knowledge": knowledge,
		"knowledge_nodes": knowledge_nodes,
		"discovered": discovered,
		"upgrades": upgrades,
		"best_floor": best_floor,
		"best_kills": best_kills,
		"last_loadout": last_loadout,
		"settings": settings,
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
	knowledge = int(parsed.get("knowledge", 0))
	knowledge_nodes = []
	for nid in parsed.get("knowledge_nodes", []):
		if Data.KNOWLEDGE_NODES.has(nid):
			knowledge_nodes.append(str(nid))
	var disc = parsed.get("discovered", {})
	if typeof(disc) == TYPE_DICTIONARY:
		for cat in ["skill", "power", "unique"]:
			discovered[cat] = disc.get(cat, {})
	best_floor = int(parsed.get("best_floor", 1))
	best_kills = int(parsed.get("best_kills", 0))
	last_loadout = str(parsed.get("last_loadout", "melee"))
	var saved_up = parsed.get("upgrades", {})
	for key in Data.UPGRADE_ORDER:
		upgrades[key] = int(saved_up.get(key, 0))
	var saved_settings = parsed.get("settings", {})
	if typeof(saved_settings) == TYPE_DICTIONARY:
		for key in settings.keys():
			if saved_settings.has(key):
				settings[key] = saved_settings[key]
