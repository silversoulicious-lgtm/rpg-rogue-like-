## Singleton (autoload) : méta-progression PERSISTANTE entre les runs.
## C'est le cœur de la boucle "à la mort, on améliore ses capacités selon le butin".
extends Node

const SAVE_PATH := "user://save.json"
# Version du schéma de sauvegarde. Incrémenter à chaque changement de forme
# des données persistées et ajouter une branche à la migration dans
# `load_game()` (ne JAMAIS planter sur une sauvegarde d'une version passée).
const SAVE_VERSION := 3

# Banque d'Éclats récoltés (monnaie méta dépensée pour les améliorations)
var shards: int = 0
# Banque de Connaissances (2ᵉ monnaie méta : débloque des systèmes via l'Arbre)
var knowledge: int = 0
# Nœuds de l'Arbre de Connaissances déjà débloqués (ids de Data.KNOWLEDGE_NODES)
var knowledge_nodes: Array = []
# Codex : éléments déjà rencontrés, par catégorie -> { id/nom: true }
var discovered: Dictionary = { "skill": {}, "relic": {}, "unique": {}, "monster": {} }
# Bestiaire (Phase 6.5) : nombre de mises à mort par sprite d'ennemi (persisté).
var kill_counts: Dictionary = {}
# Barks (Phase 6.7) : nombre de fois qu'un boss (sprite) a été affronté (persiste
# les rematchs pour varier les répliques d'intro).
var boss_faced: Dictionary = {}
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

## Bestiaire (Phase 6.5) : enregistre une mise à mort. Incrémente le compteur
## (toujours) et note la découverte dans le Codex (si débloqué). Le nom se révèle
## au 1er kill, la ligne de traits à partir de KILL_TRAITS_THRESHOLD kills.
const KILL_TRAITS_THRESHOLD := 5
func record_kill(sprite: String) -> void:
	if sprite == "":
		return
	kill_counts[sprite] = int(kill_counts.get(sprite, 0)) + 1
	# note_discovery persiste (save_game) au 1er kill ; les incréments suivants
	# sont persistés au prochain point de sauvegarde (record_run en fin de run) —
	# on évite d'écrire le disque à chaque mise à mort.
	note_discovery("monster", sprite)

func kills_of(sprite: String) -> int:
	return int(kill_counts.get(sprite, 0))

# Enregistre le bilan d'un run terminé (met à jour les records, persiste).
func record_run(stats: Dictionary) -> void:
	last_run = stats
	best_floor = max(best_floor, int(stats.get("floor", 1)))
	best_kills = max(best_kills, int(stats.get("kills", 0)))
	save_game()

# --- Sauvegarde ---------------------------------------------------------------
func save_game() -> void:
	var data := {
		"version": SAVE_VERSION,
		"shards": shards,
		"knowledge": knowledge,
		"knowledge_nodes": knowledge_nodes,
		"discovered": discovered,
		"upgrades": upgrades,
		"best_floor": best_floor,
		"best_kills": best_kills,
		"last_loadout": last_loadout,
		"settings": settings,
		"kill_counts": kill_counts,
		"boss_faced": boss_faced,
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
	var version := int(parsed.get("version", 1))
	match version:
		1, 2:
			pass   # v1/v2 : champs manquants comblés par les défauts ci-dessous.
		SAVE_VERSION:
			pass
		_:
			if version > SAVE_VERSION:
				push_warning("Sauvegarde d'une version future (%d > %d) : chargement en best-effort." % [version, SAVE_VERSION])
	shards = int(parsed.get("shards", 0))
	knowledge = int(parsed.get("knowledge", 0))
	knowledge_nodes = []
	for nid in parsed.get("knowledge_nodes", []):
		if Data.KNOWLEDGE_NODES.has(nid):
			knowledge_nodes.append(str(nid))
	var disc = parsed.get("discovered", {})
	if typeof(disc) == TYPE_DICTIONARY:
		for cat in ["skill", "relic", "unique", "monster"]:
			discovered[cat] = disc.get(cat, {})
		# Migration v2→v3 (Phase 6.4) : l'ancien bucket "power" fusionne dans "relic".
		if version < 3 and typeof(disc.get("power", {})) == TYPE_DICTIONARY:
			for key in disc.get("power", {}).keys():
				discovered["relic"][key] = true
	# Bestiaire (Phase 6.5) — absent des sauvegardes v1/v2 antérieures : défaut {}.
	var kc = parsed.get("kill_counts", {})
	kill_counts = kc if typeof(kc) == TYPE_DICTIONARY else {}
	var bf = parsed.get("boss_faced", {})   # Barks (Phase 6.7)
	boss_faced = bf if typeof(bf) == TYPE_DICTIONARY else {}
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
