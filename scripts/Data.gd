## Données statiques du jeu : héros, ennemis, équipements, artefacts, butin.
## Tout est centralisé ici pour équilibrer/ajouter du contenu facilement.
class_name Data
extends RefCounted

# --- HÉROS jouables -----------------------------------------------------------
# Stats : max_hp, atk (physique), magic (booste capacités), defense (réduction),
#         speed (100 = normal), hp_regen (PV/action).
const HEROES := {
	"knight": {
		"name": "Chevalier",
		"glyph": "@", "color": Color(0.95, 0.82, 0.35),
		"max_hp": 34, "atk": 6, "magic": 1, "defense": 3, "speed": 95, "hp_regen": 1,
		"ability_id": "whirl", "ability_name": "Tourbillon d'acier",
		"ability_desc": "Frappe TOUS les ennemis adjacents.",
		"ability_cd": 3, "ability_range": 1,
		"lore": "Garde de la Ligne de Front. Robuste, défense élevée, corps-à-corps.",
	},
	"mage": {
		"name": "Mage",
		"glyph": "@", "color": Color(0.45, 0.7, 1.0),
		"max_hp": 20, "atk": 4, "magic": 7, "defense": 1, "speed": 100, "hp_regen": 0,
		"ability_id": "bolt", "ability_name": "Éclair foudroyant",
		"ability_desc": "Foudroie l'ennemi le plus proche (dégâts magiques).",
		"ability_cd": 3, "ability_range": 6,
		"lore": "Fragile mais dévastateur. La magie démultiplie ses capacités.",
	},
	"ranger": {
		"name": "Rôdeur",
		"glyph": "@", "color": Color(0.5, 0.9, 0.5),
		"max_hp": 26, "atk": 5, "magic": 3, "defense": 2, "speed": 110, "hp_regen": 0,
		"ability_id": "volley", "ability_name": "Tir précis",
		"ability_desc": "Décoche une flèche puissante à distance.",
		"ability_cd": 2, "ability_range": 5,
		"lore": "Rapide et polyvalent. Agit plus souvent grâce à sa vitesse.",
	},
}

const HERO_ORDER := ["knight", "mage", "ranger"]

# --- ENNEMIS ------------------------------------------------------------------
const ENEMIES := [
	{ "name": "Gobelin",  "glyph": "g", "color": Color(0.5, 0.8, 0.3), "max_hp": 8,  "atk": 3, "defense": 0, "speed": 100, "shards": 2, "min_floor": 1 },
	{ "name": "Loup",     "glyph": "w", "color": Color(0.8, 0.8, 0.8), "max_hp": 10, "atk": 4, "defense": 0, "speed": 130, "shards": 3, "min_floor": 1 },
	{ "name": "Squelette","glyph": "s", "color": Color(0.9, 0.9, 0.85),"max_hp": 14, "atk": 5, "defense": 2, "speed": 100, "shards": 4, "min_floor": 3 },
	{ "name": "Orc",      "glyph": "o", "color": Color(0.4, 0.7, 0.4), "max_hp": 20, "atk": 7, "defense": 3, "speed": 90,  "shards": 6, "min_floor": 5 },
	{ "name": "Spectre",  "glyph": "S", "color": Color(0.7, 0.5, 1.0), "max_hp": 18, "atk": 9, "defense": 1, "speed": 115, "shards": 8, "min_floor": 7 },
]

const BOSS := {
	"name": "Gardien de l'Étage", "glyph": "B", "color": Color(1.0, 0.3, 0.3),
	"max_hp": 60, "atk": 10, "defense": 4, "speed": 100, "shards": 40, "min_floor": 1,
}

# --- ÉQUIPEMENT (drops, scope = run) ------------------------------------------
# Slots : "arme", "armure", "relique". Améliore les stats principales.
# glyph affiché sur la carte ; "salvage" = Éclats récupérés si on remplace/ignore.
const SLOTS := ["arme", "armure", "relique"]
const SLOT_NAMES := { "arme": "Arme", "armure": "Armure", "relique": "Relique" }
const SLOT_GLYPH := { "arme": "/", "armure": "]", "relique": "=" }
const SLOT_COLOR := {
	"arme": Color(1.0, 0.7, 0.4),
	"armure": Color(0.6, 0.75, 1.0),
	"relique": Color(0.5, 1.0, 0.8),
}

const EQUIPMENT := [
	# Armes (atk / magic / speed)
	{ "name": "Épée courte",      "slot": "arme", "min_floor": 1, "salvage": 4,  "bonus": { "atk": 2 } },
	{ "name": "Dague véloce",     "slot": "arme", "min_floor": 2, "salvage": 5,  "bonus": { "atk": 1, "speed": 15 } },
	{ "name": "Bâton runique",    "slot": "arme", "min_floor": 2, "salvage": 6,  "bonus": { "magic": 3 } },
	{ "name": "Hache de guerre",  "slot": "arme", "min_floor": 4, "salvage": 9,  "bonus": { "atk": 5, "speed": -10 } },
	{ "name": "Lame spectrale",   "slot": "arme", "min_floor": 6, "salvage": 14, "bonus": { "atk": 4, "magic": 3 } },
	# Armures (defense / max_hp)
	{ "name": "Tunique de cuir",  "slot": "armure", "min_floor": 1, "salvage": 4,  "bonus": { "defense": 2 } },
	{ "name": "Cotte de mailles", "slot": "armure", "min_floor": 3, "salvage": 8,  "bonus": { "defense": 4, "max_hp": 6, "speed": -5 } },
	{ "name": "Robe enchantée",   "slot": "armure", "min_floor": 3, "salvage": 8,  "bonus": { "defense": 1, "magic": 2, "max_hp": 4 } },
	{ "name": "Armure de plates", "slot": "armure", "min_floor": 6, "salvage": 14, "bonus": { "defense": 7, "speed": -15 } },
	{ "name": "Carapace draconique","slot": "armure","min_floor": 8, "salvage": 18, "bonus": { "defense": 5, "max_hp": 12 } },
	# Reliques (speed / hp_regen / mixte)
	{ "name": "Anneau de vitalité","slot": "relique", "min_floor": 1, "salvage": 5,  "bonus": { "max_hp": 8, "hp_regen": 1 } },
	{ "name": "Bottes ailées",    "slot": "relique", "min_floor": 2, "salvage": 6,  "bonus": { "speed": 25 } },
	{ "name": "Amulette de régén","slot": "relique", "min_floor": 4, "salvage": 9,  "bonus": { "hp_regen": 3 } },
	{ "name": "Talisman du mage", "slot": "relique", "min_floor": 4, "salvage": 10, "bonus": { "magic": 4 } },
	{ "name": "Couronne du grimpeur","slot": "relique","min_floor": 8, "salvage": 20, "bonus": { "atk": 2, "magic": 2, "defense": 2, "speed": 10, "hp_regen": 1 } },
]

# --- ARTEFACTS (drops, scope = run) -------------------------------------------
# Ajoutent une CAPACITÉ SPÉCIALE PASSIVE. "id" est lu par le moteur de combat.
const ARTIFACT_GLYPH := "✦"
const ARTIFACTS := [
	{ "id": "lifesteal", "name": "Calice de Sang",     "min_floor": 2, "color": Color(0.9, 0.2, 0.3),
	  "desc": "Vol de vie : soigne 30% des dégâts que tu infliges." },
	{ "id": "thorns",    "name": "Carapace d'Épines",  "min_floor": 2, "color": Color(0.7, 0.8, 0.4),
	  "desc": "Épines : renvoie des dégâts à qui te frappe." },
	{ "id": "crit",      "name": "Croc Sauvage",       "min_floor": 3, "color": Color(1.0, 0.5, 0.2),
	  "desc": "25% de chances d'infliger un coup critique (x2)." },
	{ "id": "dodge",     "name": "Voile d'Ombre",      "min_floor": 3, "color": Color(0.6, 0.4, 0.9),
	  "desc": "20% de chances d'esquiver complètement une attaque." },
	{ "id": "phoenix",   "name": "Plume de Phénix",    "min_floor": 5, "color": Color(1.0, 0.75, 0.25),
	  "desc": "Une fois par run : ressuscite à 50% PV au lieu de mourir." },
]

# --- AMÉLIORATIONS MÉTA (entre les runs) --------------------------------------
const UPGRADES := {
	"vitalite": { "name": "Vitalité",  "desc": "+5 PV max",                "base_cost": 12 },
	"force":    { "name": "Force",     "desc": "+1 Attaque",               "base_cost": 15 },
	"maitrise": { "name": "Maîtrise",  "desc": "+2 puissance de capacité", "base_cost": 18 },
}
const UPGRADE_ORDER := ["vitalite", "force", "maitrise"]

static func upgrade_cost(key: String, level: int) -> int:
	return UPGRADES[key]["base_cost"] + level * UPGRADES[key]["base_cost"]

# Résumé court d'un bonus d'équipement, pour l'affichage.
static func bonus_summary(bonus: Dictionary) -> String:
	var parts: Array = []
	var labels := { "atk": "ATK", "magic": "MAG", "defense": "DEF", "speed": "VIT", "max_hp": "PV", "hp_regen": "REGEN" }
	for k in ["atk", "magic", "defense", "speed", "max_hp", "hp_regen"]:
		if bonus.has(k):
			var v: int = int(bonus[k])
			parts.append("%s%+d" % [labels[k], v])
	return ", ".join(parts)
