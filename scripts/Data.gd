## Données statiques du jeu : héros, ennemis, butin.
## Tout est centralisé ici pour qu'on puisse équilibrer/ajouter du contenu facilement.
class_name Data
extends RefCounted

# --- HÉROS jouables -----------------------------------------------------------
# ability_id : "whirl" (zone corps-à-corps), "bolt" (éclair à distance),
#              "volley" (tir précis à distance)
const HEROES := {
	"knight": {
		"name": "Chevalier",
		"glyph": "@",
		"color": Color(0.95, 0.82, 0.35),   # or
		"max_hp": 34,
		"atk": 6,
		"ability_id": "whirl",
		"ability_name": "Tourbillon d'acier",
		"ability_desc": "Frappe TOUS les ennemis adjacents.",
		"ability_cd": 3,
		"ability_range": 1,
		"lore": "Garde de la Ligne de Front. Robuste, frappe au corps-à-corps.",
	},
	"mage": {
		"name": "Mage",
		"glyph": "@",
		"color": Color(0.45, 0.7, 1.0),     # bleu
		"max_hp": 20,
		"atk": 5,
		"ability_id": "bolt",
		"ability_name": "Éclair foudroyant",
		"ability_desc": "Foudroie l'ennemi le plus proche en ligne de vue.",
		"ability_cd": 3,
		"ability_range": 6,
		"lore": "Fragile mais dévastateur à distance. Gère ton positionnement.",
	},
	"ranger": {
		"name": "Rôdeur",
		"glyph": "@",
		"color": Color(0.5, 0.9, 0.5),      # vert
		"max_hp": 26,
		"atk": 5,
		"ability_id": "volley",
		"ability_name": "Tir précis",
		"ability_desc": "Décoche une flèche puissante sur l'ennemi le plus proche.",
		"ability_cd": 2,
		"ability_range": 5,
		"lore": "Polyvalent. Bon contrôle de la distance.",
	},
}

const HERO_ORDER := ["knight", "mage", "ranger"]

# --- ENNEMIS ------------------------------------------------------------------
# min_floor : étage minimum d'apparition. Les stats montent avec l'étage (voir Dungeon).
const ENEMIES := [
	{ "name": "Gobelin", "glyph": "g", "color": Color(0.5, 0.8, 0.3), "max_hp": 8,  "atk": 3, "shards": 2, "min_floor": 1 },
	{ "name": "Loup",    "glyph": "w", "color": Color(0.8, 0.8, 0.8), "max_hp": 10, "atk": 4, "shards": 3, "min_floor": 1 },
	{ "name": "Squelette","glyph": "s","color": Color(0.9, 0.9, 0.85),"max_hp": 14, "atk": 5, "shards": 4, "min_floor": 3 },
	{ "name": "Orc",     "glyph": "o", "color": Color(0.4, 0.7, 0.4), "max_hp": 20, "atk": 7, "shards": 6, "min_floor": 5 },
	{ "name": "Spectre", "glyph": "S", "color": Color(0.7, 0.5, 1.0), "max_hp": 18, "atk": 9, "shards": 8, "min_floor": 7 },
]

const BOSS := {
	"name": "Gardien de l'Étage", "glyph": "B", "color": Color(1.0, 0.3, 0.3),
	"max_hp": 60, "atk": 10, "shards": 40, "min_floor": 1,
}

# --- AMÉLIORATIONS MÉTA (entre les runs) --------------------------------------
# Achetées avec les Éclats récoltés dans le donjon. Persistent après la mort.
const UPGRADES := {
	"vitalite": { "name": "Vitalité",  "desc": "+5 PV max",            "base_cost": 12 },
	"force":    { "name": "Force",     "desc": "+1 Attaque",           "base_cost": 15 },
	"maitrise": { "name": "Maîtrise",  "desc": "+2 puissance de capacité", "base_cost": 18 },
}

const UPGRADE_ORDER := ["vitalite", "force", "maitrise"]

static func upgrade_cost(key: String, level: int) -> int:
	return UPGRADES[key]["base_cost"] + level * UPGRADES[key]["base_cost"]
