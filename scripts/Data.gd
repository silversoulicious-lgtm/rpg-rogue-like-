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
	{ "name": "Gobelin",  "glyph": "g", "sprite": "gobelin",   "color": Color(0.5, 0.8, 0.3), "max_hp": 8,  "atk": 3, "defense": 0, "speed": 100, "shards": 2, "min_floor": 1 },
	{ "name": "Loup",     "glyph": "w", "sprite": "loup",      "color": Color(0.8, 0.8, 0.8), "max_hp": 10, "atk": 4, "defense": 0, "speed": 130, "shards": 3, "min_floor": 1 },
	{ "name": "Squelette","glyph": "s", "sprite": "squelette", "color": Color(0.9, 0.9, 0.85),"max_hp": 14, "atk": 5, "defense": 2, "speed": 100, "shards": 4, "min_floor": 3 },
	{ "name": "Orc",      "glyph": "o", "sprite": "orc",       "color": Color(0.4, 0.7, 0.4), "max_hp": 20, "atk": 7, "defense": 3, "speed": 90,  "shards": 6, "min_floor": 5 },
	{ "name": "Spectre",  "glyph": "S", "sprite": "spectre",   "color": Color(0.7, 0.5, 1.0), "max_hp": 18, "atk": 9, "defense": 1, "speed": 115, "shards": 8, "min_floor": 7 },
]

const BOSS := {
	"name": "Gardien de l'Étage", "glyph": "B", "sprite": "boss", "color": Color(1.0, 0.3, 0.3),
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

# --- GÉNÉRATION PROCÉDURALE D'OBJETS ------------------------------------------
# Bases d'objets : donnent une stat "primaire" garantie, puis des affixes s'ajoutent.
const ITEM_BASES := [
	{ "name": "Dague",    "slot": "arme",    "primary": { "atk": 1, "speed": 8 } },
	{ "name": "Épée",     "slot": "arme",    "primary": { "atk": 3 } },
	{ "name": "Hache",    "slot": "arme",    "primary": { "atk": 5, "speed": -5 } },
	{ "name": "Bâton",    "slot": "arme",    "primary": { "magic": 4 } },
	{ "name": "Tunique",  "slot": "armure",  "primary": { "defense": 2 } },
	{ "name": "Cotte",    "slot": "armure",  "primary": { "defense": 4, "max_hp": 4 } },
	{ "name": "Plastron", "slot": "armure",  "primary": { "defense": 6, "speed": -5 } },
	{ "name": "Robe",     "slot": "armure",  "primary": { "defense": 1, "magic": 3, "max_hp": 3 } },
	{ "name": "Anneau",   "slot": "relique", "primary": { "max_hp": 6, "hp_regen": 1 } },
	{ "name": "Amulette", "slot": "relique", "primary": { "magic": 3 } },
	{ "name": "Bottes",   "slot": "relique", "primary": { "speed": 18 } },
	{ "name": "Talisman", "slot": "relique", "primary": { "hp_regen": 2, "max_hp": 4 } },
]

# Raretés : nb d'affixes, multiplicateur de valeur, valeur de recyclage, poids de base.
const RARITIES := [
	{ "id": "commun",     "name": "Commun",     "color": Color(0.78, 0.78, 0.82), "affixes": 0, "mult": 1.0, "salvage": 3,  "weight": 58.0, "wfloor": -3.0 },
	{ "id": "rare",       "name": "Rare",       "color": Color(0.45, 0.7, 1.0),   "affixes": 1, "mult": 1.15,"salvage": 7,  "weight": 28.0, "wfloor": 1.0 },
	{ "id": "epique",     "name": "Épique",     "color": Color(0.75, 0.45, 1.0),  "affixes": 2, "mult": 1.35,"salvage": 14, "weight": 11.0, "wfloor": 1.6 },
	{ "id": "legendaire", "name": "Légendaire", "color": Color(1.0, 0.78, 0.3),   "affixes": 3, "mult": 1.6, "salvage": 26, "weight": 3.0,  "wfloor": 0.7 },
]

# Affixes : clé de stat -> {nom, min, max, float?}. Les entiers montent avec l'étage.
const AFFIXES := [
	{ "key": "atk",          "name": "de Force",       "min": 1,    "max": 3 },
	{ "key": "magic",        "name": "de l'Arcane",    "min": 1,    "max": 3 },
	{ "key": "defense",      "name": "du Gardien",     "min": 1,    "max": 3 },
	{ "key": "speed",        "name": "de Hâte",        "min": 6,    "max": 14 },
	{ "key": "max_hp",       "name": "de Vitalité",    "min": 4,    "max": 10 },
	{ "key": "hp_regen",     "name": "de Régén.",      "min": 1,    "max": 2 },
	{ "key": "crit_chance",  "name": "de Précision",   "min": 0.05, "max": 0.12, "is_float": true },
	{ "key": "dodge_chance", "name": "d'Esquive",      "min": 0.05, "max": 0.10, "is_float": true },
	{ "key": "lifesteal_pct","name": "du Vampire",     "min": 0.05, "max": 0.12, "is_float": true },
	{ "key": "thorns_flat",  "name": "des Épines",     "min": 2,    "max": 5 },
]

# --- OBJETS UNIQUES (Épique/Légendaire) ---------------------------------------
# Au-delà de la rareté = "plus de stats", les paliers Épique et Légendaire
# puisent dans une bibliothèque d'objets NOMMÉS, chacun porteur d'un EFFET DE
# COMBAT unique (proc) en plus de ses stats fixes. Légendaire = version
# amplifiée (stats ×1.4, effet ×1.3) de la même identité, avec une épithète.
const UNIQUE_EPITHETS := [
	"Ancestral", "Maudit", "du Crépuscule", "Éternel", "Sacré", "des Abysses",
	"Oublié", "du Jugement", "Céleste", "Funeste", "de Sang", "des Ombres",
	"Inflexible", "du Néant", "Radieux", "Vengeur", "Immuable",
]

# id du proc -> (générée par _proc_desc). Effets gérés par Main.gd (combat).
# "execution"     : +val% dégâts contre une cible sous 25% PV.
# "frenesie"      : +val% dégâts quand le porteur est sous 40% PV.
# "premier_coup"  : la 1re attaque de chaque combat est un critique garanti.
# "frappe_double" : val% de chances de frapper une 2e fois (50% dégâts).
# "soif_de_sang"  : soigne val% PV max à chaque ennemi tué.
# "moisson"       : +val Éclats à chaque ennemi tué.
const UNIQUE_BASES := [
	# --- ARME (17) ---
	{ "name": "Lame des Damnés",      "slot": "arme", "stat": { "atk": 6 },                "proc": "execution",     "val": 0.50 },
	{ "name": "Hache du Bourreau",    "slot": "arme", "stat": { "atk": 8, "speed": -4 },    "proc": "frenesie",      "val": 0.30 },
	{ "name": "Dague du Silence",     "slot": "arme", "stat": { "atk": 3, "speed": 10 },    "proc": "premier_coup",  "val": 1.0 },
	{ "name": "Marteau du Tyran",     "slot": "arme", "stat": { "atk": 9, "defense": 1 },   "proc": "frappe_double", "val": 0.25 },
	{ "name": "Croc Ancestral",       "slot": "arme", "stat": { "atk": 5 },                 "proc": "soif_de_sang",  "val": 0.12 },
	{ "name": "Faux du Faucheur",     "slot": "arme", "stat": { "atk": 7 },                 "proc": "moisson",       "val": 4.0 },
	{ "name": "Épée du Sacrifice",    "slot": "arme", "stat": { "atk": 8, "max_hp": -6 },   "proc": "execution",     "val": 0.65 },
	{ "name": "Bâton des Cendres",    "slot": "arme", "stat": { "magic": 6 },               "proc": "frenesie",      "val": 0.35 },
	{ "name": "Arc du Vent",          "slot": "arme", "stat": { "atk": 4, "speed": 12 },    "proc": "premier_coup",  "val": 1.0 },
	{ "name": "Sceptre Runique",      "slot": "arme", "stat": { "magic": 7, "defense": 1 }, "proc": "frappe_double", "val": 0.22 },
	{ "name": "Lame Jumelle",         "slot": "arme", "stat": { "atk": 5, "speed": 6 },     "proc": "soif_de_sang",  "val": 0.14 },
	{ "name": "Hallebarde de Garde",  "slot": "arme", "stat": { "atk": 6, "defense": 2 },   "proc": "moisson",       "val": 5.0 },
	{ "name": "Poignard Vicieux",     "slot": "arme", "stat": { "atk": 4 },                 "proc": "execution",     "val": 0.55 },
	{ "name": "Fléau Sacré",          "slot": "arme", "stat": { "atk": 7, "magic": 2 },     "proc": "frenesie",      "val": 0.30 },
	{ "name": "Bâton du Sage Fou",    "slot": "arme", "stat": { "magic": 8, "speed": -3 },  "proc": "premier_coup",  "val": 1.0 },
	{ "name": "Lame Spectrale",       "slot": "arme", "stat": { "atk": 5, "speed": 8 },     "proc": "frappe_double", "val": 0.28 },
	{ "name": "Glaive du Crépuscule", "slot": "arme", "stat": { "atk": 8 },                 "proc": "moisson",       "val": 4.0 },
	# --- ARMURE (17) ---
	{ "name": "Cuirasse des Damnés",  "slot": "armure", "stat": { "defense": 5, "max_hp": 8 },  "proc": "execution",     "val": 0.45 },
	{ "name": "Plastron du Tyran",    "slot": "armure", "stat": { "defense": 7, "speed": -6 },  "proc": "frenesie",      "val": 0.32 },
	{ "name": "Tunique de l'Ombre",   "slot": "armure", "stat": { "defense": 2, "speed": 8 },   "proc": "premier_coup",  "val": 1.0 },
	{ "name": "Armure du Jugement",   "slot": "armure", "stat": { "defense": 6, "max_hp": 4 },  "proc": "frappe_double", "val": 0.20 },
	{ "name": "Cotte Ancestrale",     "slot": "armure", "stat": { "defense": 5, "hp_regen": 2 },"proc": "soif_de_sang",  "val": 0.13 },
	{ "name": "Carapace du Gardien",  "slot": "armure", "stat": { "defense": 8, "speed": -5 },  "proc": "moisson",       "val": 5.0 },
	{ "name": "Robe des Cendres",     "slot": "armure", "stat": { "defense": 2, "magic": 4 },   "proc": "execution",     "val": 0.40 },
	{ "name": "Bouclier Vivant",      "slot": "armure", "stat": { "defense": 6, "max_hp": 6 },  "proc": "frenesie",      "val": 0.30 },
	{ "name": "Manteau Funeste",      "slot": "armure", "stat": { "defense": 3, "speed": 6 },   "proc": "premier_coup",  "val": 1.0 },
	{ "name": "Plaque Céleste",       "slot": "armure", "stat": { "defense": 7, "max_hp": 5 },  "proc": "frappe_double", "val": 0.20 },
	{ "name": "Vêture Sacrée",        "slot": "armure", "stat": { "defense": 4, "hp_regen": 1, "max_hp": 4 }, "proc": "soif_de_sang", "val": 0.14 },
	{ "name": "Armure du Néant",      "slot": "armure", "stat": { "defense": 5, "magic": 2 },   "proc": "moisson",       "val": 5.0 },
	{ "name": "Cuirasse Vengeresse",  "slot": "armure", "stat": { "defense": 6, "atk": 2 },     "proc": "execution",     "val": 0.45 },
	{ "name": "Tunique Inflexible",   "slot": "armure", "stat": { "defense": 4, "max_hp": 6 },   "proc": "frenesie",      "val": 0.30 },
	{ "name": "Harnais Radieux",      "slot": "armure", "stat": { "defense": 5, "speed": 4 },    "proc": "premier_coup",  "val": 1.0 },
	{ "name": "Plastron Immuable",    "slot": "armure", "stat": { "defense": 9, "speed": -8 },   "proc": "frappe_double", "val": 0.22 },
	{ "name": "Cape des Abysses",     "slot": "armure", "stat": { "defense": 3, "speed": 10 },   "proc": "soif_de_sang",  "val": 0.13 },
	# --- RELIQUE (17) ---
	{ "name": "Anneau des Damnés",    "slot": "relique", "stat": { "max_hp": 6, "hp_regen": 1 },  "proc": "moisson",       "val": 5.0 },
	{ "name": "Amulette du Tyran",    "slot": "relique", "stat": { "magic": 5, "atk": 2 },        "proc": "execution",     "val": 0.45 },
	{ "name": "Bottes du Silence",    "slot": "relique", "stat": { "speed": 16 },                  "proc": "frenesie",      "val": 0.30 },
	{ "name": "Talisman du Jugement", "slot": "relique", "stat": { "hp_regen": 3, "max_hp": 4 },  "proc": "premier_coup",  "val": 1.0 },
	{ "name": "Sceau Ancestral",      "slot": "relique", "stat": { "defense": 2, "magic": 3 },    "proc": "frappe_double", "val": 0.22 },
	{ "name": "Couronne du Gardien",  "slot": "relique", "stat": { "magic": 4, "max_hp": 5 },     "proc": "soif_de_sang",  "val": 0.13 },
	{ "name": "Pendentif des Cendres","slot": "relique", "stat": { "hp_regen": 2, "speed": 6 },   "proc": "moisson",       "val": 5.0 },
	{ "name": "Gantelet Vivant",      "slot": "relique", "stat": { "atk": 3, "max_hp": 4 },       "proc": "execution",     "val": 0.45 },
	{ "name": "Anneau Funeste",       "slot": "relique", "stat": { "atk": 2, "magic": 2 },        "proc": "frenesie",      "val": 0.30 },
	{ "name": "Boucle Céleste",       "slot": "relique", "stat": { "speed": 10, "hp_regen": 1 },  "proc": "premier_coup",  "val": 1.0 },
	{ "name": "Relique Sacrée",       "slot": "relique", "stat": { "max_hp": 8 },                 "proc": "frappe_double", "val": 0.22 },
	{ "name": "Orbe du Néant",        "slot": "relique", "stat": { "magic": 6 },                  "proc": "soif_de_sang",  "val": 0.13 },
	{ "name": "Chaîne Vengeresse",    "slot": "relique", "stat": { "atk": 2, "defense": 2 },      "proc": "moisson",       "val": 5.0 },
	{ "name": "Bracelet Inflexible",  "slot": "relique", "stat": { "defense": 3, "max_hp": 4 },   "proc": "execution",     "val": 0.40 },
	{ "name": "Idole Radieuse",       "slot": "relique", "stat": { "magic": 3, "hp_regen": 2 },   "proc": "frenesie",      "val": 0.30 },
	{ "name": "Émeraude Immuable",    "slot": "relique", "stat": { "defense": 2, "speed": 8 },    "proc": "premier_coup",  "val": 1.0 },
	{ "name": "Fiole des Abysses",    "slot": "relique", "stat": { "hp_regen": 3 },               "proc": "frappe_double", "val": 0.22 },
]

static func _proc_desc(proc: String, val: float) -> String:
	match proc:
		"execution": return "Exécution : +%d%% dégâts contre les ennemis sous 25%% PV." % int(round(val * 100))
		"frenesie": return "Frénésie : +%d%% dégâts quand tu es sous 40%% PV." % int(round(val * 100))
		"premier_coup": return "Premier Coup : la 1re attaque de chaque combat est un critique garanti."
		"frappe_double": return "Frappe Double : %d%% de chances de frapper une 2e fois (50%% dégâts)." % int(round(val * 100))
		"soif_de_sang": return "Soif de Sang : soigne %d%% PV max à chaque ennemi tué." % int(round(val * 100))
		"moisson": return "Moisson : +%d Éclats à chaque ennemi tué." % int(round(val))
		_: return ""

## Construit le pool complet (Épique + Légendaire, 102 objets) une seule fois.
static func _build_unique_pool() -> Array:
	var out: Array = []
	for i in UNIQUE_BASES.size():
		var b: Dictionary = UNIQUE_BASES[i]
		out.append({
			"name": b["name"], "slot": b["slot"], "rarity": "epique",
			"stat": b["stat"], "proc": b["proc"], "proc_val": b["val"],
			"desc": _proc_desc(b["proc"], b["val"]),
		})
		var stat_l: Dictionary = {}
		for k in b["stat"]:
			stat_l[k] = int(round(float(b["stat"][k]) * 1.4))
		var val_l: float = b["val"] * 1.3
		out.append({
			"name": "%s, %s" % [b["name"], UNIQUE_EPITHETS[i % UNIQUE_EPITHETS.size()]],
			"slot": b["slot"], "rarity": "legendaire",
			"stat": stat_l, "proc": b["proc"], "proc_val": val_l,
			"desc": _proc_desc(b["proc"], val_l),
		})
	return out

static var UNIQUE_ITEMS: Array = _build_unique_pool()

# --- SYNERGIES INTER-PROCS ----------------------------------------------------
# Quand le porteur équipe simultanément deux procs complémentaires, une synergie
# nommée s'active et AMPLIFIE la valeur des procs concernés de "boost".
# Détectée et appliquée dans Entity.recompute_stats ; affichée dans la HUD.
const SYNERGIES := [
	{ "id": "rage_sanguinaire", "name": "Rage Sanguinaire", "requires": ["soif_de_sang", "frenesie"],
	  "boost": 0.20, "color": Color(0.95, 0.25, 0.35),
	  "desc": "Soif de Sang + Frénésie : les deux procs amplifiés de 20%." },
	{ "id": "bourreau", "name": "Sentence du Bourreau", "requires": ["execution", "premier_coup"],
	  "boost": 0.25, "color": Color(0.8, 0.4, 1.0),
	  "desc": "Exécution + Premier Coup : l'exécution amplifiée de 25%." },
	{ "id": "tempete_lames", "name": "Tempête de Lames", "requires": ["frappe_double", "premier_coup"],
	  "boost": 0.20, "color": Color(0.6, 0.85, 1.0),
	  "desc": "Frappe Double + Premier Coup : frappe double amplifiée de 20%." },
	{ "id": "recolte_macabre", "name": "Récolte Macabre", "requires": ["moisson", "soif_de_sang"],
	  "boost": 0.20, "color": Color(1.0, 0.8, 0.3),
	  "desc": "Moisson + Soif de Sang : les deux procs amplifiés de 20%." },
	{ "id": "predateur", "name": "Prédateur Affamé", "requires": ["execution", "frenesie"],
	  "boost": 0.20, "color": Color(1.0, 0.45, 0.3),
	  "desc": "Exécution + Frénésie : les deux procs amplifiés de 20%." },
]

static func _pick_unique(slot: String, rarity_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var pool: Array = []
	for it in UNIQUE_ITEMS:
		if it["slot"] == slot and it["rarity"] == rarity_id:
			pool.append(it)
	if pool.is_empty():
		return {}
	return pool[rng.randi_range(0, pool.size() - 1)]

## Génère un objet d'équipement aléatoire pour un slot donné et un étage.
## Épique/Légendaire puisent dans la bibliothèque d'objets uniques (UNIQUE_ITEMS).
static func generate_item(slot: String, floor: int, rng: RandomNumberGenerator) -> Dictionary:
	var rarity: Dictionary = _pick_rarity(floor, rng)
	if rarity["id"] == "epique" or rarity["id"] == "legendaire":
		var uniq: Dictionary = _pick_unique(slot, rarity["id"], rng)
		if not uniq.is_empty():
			return _make_unique_item(slot, floor, rarity, uniq)
	return _generate_procedural_item(slot, floor, rarity, rng)

## Assemble un objet d'équipement unique (stats mises à l'échelle de l'étage + proc).
static func _make_unique_item(slot: String, floor: int, rarity: Dictionary, uniq: Dictionary) -> Dictionary:
	var uscale: float = 1.0 + float(floor - 1) * 0.05
	var ubonus: Dictionary = {}
	for k in uniq["stat"]:
		ubonus[k] = int(round(float(uniq["stat"][k]) * uscale))
	return {
		"kind": "equip", "name": uniq["name"], "slot": slot, "unique": true,
		"rarity": rarity["id"], "rarity_name": rarity["name"], "rarity_color": rarity["color"],
		"bonus": ubonus, "salvage": int(rarity["salvage"]) + floor, "sprite": slot,
		"proc": uniq["proc"], "proc_val": uniq["proc_val"], "desc": uniq["desc"],
	}

static func rarity_by_id(id: String) -> Dictionary:
	for r in RARITIES:
		if r["id"] == id:
			return r
	return RARITIES[0]

## Récompense GARANTIE Épique+ d'un boss : objet unique nommé (35% Légendaire).
static func generate_boss_reward(floor: int, rng: RandomNumberGenerator) -> Dictionary:
	var slot: String = SLOTS[rng.randi_range(0, SLOTS.size() - 1)]
	var rid: String = "legendaire" if rng.randf() < 0.35 else "epique"
	var uniq: Dictionary = _pick_unique(slot, rid, rng)
	if uniq.is_empty():
		uniq = _pick_unique(slot, "epique", rng)
		rid = "epique"
	return _make_unique_item(slot, floor, rarity_by_id(rid), uniq)

static func _generate_procedural_item(slot: String, floor: int, rarity: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var bases: Array = []
	for b in ITEM_BASES:
		if b["slot"] == slot:
			bases.append(b)
	var base: Dictionary = bases[rng.randi_range(0, bases.size() - 1)]
	var fscale: float = 1.0 + float(floor - 1) * 0.08
	var bonus: Dictionary = {}
	for k in base["primary"]:
		var v: float = float(base["primary"][k]) * fscale * rarity["mult"]
		bonus[k] = int(round(v)) + int(bonus.get(k, 0))
	var affix_names: Array = []
	for i in range(int(rarity["affixes"])):
		var af: Dictionary = AFFIXES[rng.randi_range(0, AFFIXES.size() - 1)]
		var key: String = af["key"]
		if af.get("is_float", false):
			var fv: float = rng.randf_range(af["min"], af["max"])
			bonus[key] = float(bonus.get(key, 0.0)) + snappedf(fv, 0.01)
			affix_names.append(af["name"])
		else:
			var iv: int = int(round(rng.randi_range(af["min"], af["max"]) * fscale))
			bonus[key] = int(bonus.get(key, 0)) + iv
			affix_names.append(af["name"])
	var name: String = base["name"]
	if not affix_names.is_empty():
		name += " " + affix_names[0]
	return {
		"kind": "equip", "name": name, "slot": slot,
		"rarity": rarity["id"], "rarity_name": rarity["name"], "rarity_color": rarity["color"],
		"bonus": bonus, "salvage": int(rarity["salvage"]) + floor, "sprite": slot,
	}

static func _pick_rarity(floor: int, rng: RandomNumberGenerator) -> Dictionary:
	var weights: Array = []
	var total: float = 0.0
	for r in RARITIES:
		var w: float = maxf(2.0, float(r["weight"]) + float(r["wfloor"]) * float(floor))
		weights.append(w)
		total += w
	var roll: float = rng.randf() * total
	for i in RARITIES.size():
		roll -= weights[i]
		if roll <= 0.0:
			return RARITIES[i]
	return RARITIES[0]

# --- CONSOMMABLES (drops, scope = run) ----------------------------------------
const CONSUMABLES := [
	{ "id": "potion",  "name": "Potion de soin",   "effect": "heal_pct",  "value": 0.40, "weight": 5.0, "color": Color(0.95, 0.3, 0.4) },
	{ "id": "potion_g","name": "Grande potion",    "effect": "heal_pct",  "value": 0.75, "weight": 3.0, "color": Color(0.95, 0.3, 0.4) },
	{ "id": "elixir",  "name": "Élixir de vie",    "effect": "heal_full", "value": 1.0,  "weight": 1.0, "color": Color(0.9, 0.5, 0.9) },
	{ "id": "crystal", "name": "Cristal d'Éclats", "effect": "shards",    "value": 12.0, "weight": 2.0, "color": Color(1.0, 0.85, 0.35) },
]

static func generate_consumable(floor: int, rng: RandomNumberGenerator) -> Dictionary:
	var total: float = 0.0
	for c in CONSUMABLES:
		total += float(c["weight"])
	var roll: float = rng.randf() * total
	for c in CONSUMABLES:
		roll -= float(c["weight"])
		if roll <= 0.0:
			var item: Dictionary = c.duplicate(true)
			item["kind"] = "consumable"
			item["sprite"] = "potion"
			if c["effect"] == "shards":
				item["value"] = float(c["value"]) + floor
			return item
	return CONSUMABLES[0].duplicate(true)

# --- TALENTS (choix de montée de niveau pendant un run) -----------------------
const TALENTS := [
	{ "id": "vigueur",   "name": "Vigueur",       "desc": "+12 PV max",                 "mods": { "max_hp": 12 } },
	{ "id": "puissance", "name": "Puissance",     "desc": "+2 Attaque",                 "mods": { "atk": 2 } },
	{ "id": "arcane",    "name": "Arcane",        "desc": "+3 Magie",                   "mods": { "magic": 3 } },
	{ "id": "carapace",  "name": "Carapace",      "desc": "+2 Défense",                 "mods": { "defense": 2 } },
	{ "id": "celerite",  "name": "Célérité",      "desc": "+15 Vitesse",                "mods": { "speed": 15 } },
	{ "id": "regen",     "name": "Régénération",  "desc": "+2 Régén PV/tour",           "mods": { "hp_regen": 2 } },
	{ "id": "precision", "name": "Précision",     "desc": "+10% Coup critique",         "mods": { "crit_chance": 0.10 } },
	{ "id": "agilite",   "name": "Agilité",       "desc": "+10% Esquive",               "mods": { "dodge_chance": 0.10 } },
	{ "id": "sangsue",   "name": "Sangsue",       "desc": "+12% Vol de vie",            "mods": { "lifesteal_pct": 0.12 } },
	{ "id": "represaille","name": "Représailles", "desc": "+4 Épines",                  "mods": { "thorns_flat": 4 } },
	{ "id": "affutage",  "name": "Affûtage",      "desc": "+3 puissance de capacité",   "mods": { "ability_power": 3 } },
	{ "id": "focus",     "name": "Concentration", "desc": "-1 recharge de capacité",    "mods": { "ability_cd": -1 } },
	{ "id": "phenix",    "name": "Second souffle","desc": "+1 résurrection (50% PV)",   "mods": { "max_revives": 1 } },
	{ "id": "brutalite", "name": "Brutalité",     "desc": "+1 ATK et +6% critique",     "mods": { "atk": 1, "crit_chance": 0.06 } },
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

# Effets des artefacts, exprimés comme modificateurs (lus par Entity.recompute_stats).
const ARTIFACT_MODS := {
	"lifesteal": { "lifesteal_pct": 0.30 },
	"thorns":    { "thorns_flat": 4 },
	"crit":      { "crit_chance": 0.25 },
	"dodge":     { "dodge_chance": 0.20 },
	"phoenix":   { "max_revives": 1 },
}

# --- ÉVÉNEMENTS (salles "?") --------------------------------------------------
# Chaque choix porte un "type" interprété par Main._apply_event_effect.
const EVENTS := [
	{ "title": "Fontaine scintillante", "desc": "Une eau claire jaillit d'une source oubliée.",
	  "choices": [
		{ "label": "Boire (+40% PV)", "type": "heal", "value": 0.40 },
		{ "label": "Remplir une fiole (1 consommable)", "type": "item_consumable" } ] },
	{ "title": "Coffre suspect", "desc": "Un coffre orné… peut-être piégé.",
	  "choices": [
		{ "label": "Forcer l'ouverture (pari)", "type": "gamble" },
		{ "label": "Passer son chemin", "type": "none" } ] },
	{ "title": "Marchand errant", "desc": "Une silhouette encapuchonnée propose un troc.",
	  "choices": [
		{ "label": "Troquer 20 Éclats contre un artefact", "type": "trade_artifact" },
		{ "label": "Décliner", "type": "none" } ] },
	{ "title": "Forge ancienne", "desc": "Une enclume rougeoie encore. Tu peux affûter ton corps.",
	  "choices": [
		{ "label": "Renforcer ses bras (+3 ATK ce run)", "type": "stat_atk" },
		{ "label": "Tremper sa peau (+15 PV max ce run)", "type": "stat_hp" } ] },
	{ "title": "Pèlerin blessé", "desc": "Un voyageur agonisant murmure une bénédiction.",
	  "choices": [
		{ "label": "L'aider (−15 Éclats, +1 résurrection)", "type": "buy_revive" },
		{ "label": "L'ignorer (+12 Éclats)", "type": "shards", "value": 12 } ] },
	{ "title": "Autel maudit", "desc": "Une dalle noire réclame un sacrifice de chair contre la puissance brute.",
	  "choices": [
		{ "label": "Offrir sa vigueur (+5 ATK, −10 PV max ce run)", "type": "cursed_altar" },
		{ "label": "Reculer prudemment", "type": "none" } ] },
	{ "title": "Sanctuaire oublié", "desc": "Une lumière douce émane d'un autel resté intact à travers les âges.",
	  "choices": [
		{ "label": "Se recueillir (+60% PV)", "type": "heal", "value": 0.60 },
		{ "label": "Méditer (+1 Régén PV/tour ce run)", "type": "stat_regen" } ] },
]

# --- AMÉLIORATIONS MÉTA (entre les runs) --------------------------------------
const UPGRADES := {
	"vitalite": { "name": "Vitalité",  "desc": "+5 PV max",                       "base_cost": 12, "max": 8 },
	"force":    { "name": "Force",     "desc": "+1 Attaque",                      "base_cost": 15, "max": 8 },
	"maitrise": { "name": "Maîtrise",  "desc": "+2 puissance de capacité",        "base_cost": 18, "max": 6 },
	"fortune":  { "name": "Fortune",   "desc": "+15 Éclats au départ du run",     "base_cost": 20, "max": 5 },
	"heritage": { "name": "Héritage",  "desc": "Démarre avec un artefact de plus","base_cost": 40, "max": 2 },
	"instinct": { "name": "Instinct",  "desc": "Démarre avec un talent de plus",  "base_cost": 45, "max": 2 },
}
const UPGRADE_ORDER := ["vitalite", "force", "maitrise", "fortune", "heritage", "instinct"]

static func upgrade_cost(key: String, level: int) -> int:
	return UPGRADES[key]["base_cost"] + level * UPGRADES[key]["base_cost"]

static func upgrade_max(key: String) -> int:
	return int(UPGRADES[key].get("max", 99))

# Résumé court d'un bonus d'objet, pour l'affichage.
static func bonus_summary(bonus: Dictionary) -> String:
	var parts: Array = []
	for k in ["atk", "magic", "defense", "speed", "max_hp", "hp_regen"]:
		if bonus.has(k) and int(bonus[k]) != 0:
			parts.append("%s%+d" % [{ "atk": "ATK", "magic": "MAG", "defense": "DEF", "speed": "VIT", "max_hp": "PV", "hp_regen": "REGEN" }[k], int(bonus[k])])
	for k in ["crit_chance", "dodge_chance", "lifesteal_pct"]:
		if bonus.has(k) and float(bonus[k]) != 0.0:
			parts.append("%s+%d%%" % [{ "crit_chance": "CRIT", "dodge_chance": "ESQ", "lifesteal_pct": "VAMP" }[k], int(round(float(bonus[k]) * 100.0))])
	if bonus.has("thorns_flat") and int(bonus["thorns_flat"]) != 0:
		parts.append("ÉPINES+%d" % int(bonus["thorns_flat"]))
	return ", ".join(parts)
