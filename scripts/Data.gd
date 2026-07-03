## Données statiques du jeu : héros, ennemis, équipements, artefacts, butin.
## Tout est centralisé ici pour équilibrer/ajouter du contenu facilement.
class_name Data
extends RefCounted

# --- HÉROÏNE (personnage unique) ----------------------------------------------
# Le jeu suit UNE héroïne ; son identité de build provient de l'ARME équipée
# (cf. ARMES / COMPÉTENCES ci-dessous), pas d'une classe.
# Stats : max_hp, atk (physique), magic (booste capacités), defense (réduction),
#         speed (100 = normal), hp_regen (PV/action).
const HEROINE := {
	"name": "Aria",
	"glyph": "@", "color": Color(0.92, 0.55, 0.85),
	"sprite": "aria",   # sprite dédié de l'héroïne
	"max_hp": 28, "atk": 5, "magic": 3, "defense": 2, "speed": 100, "hp_regen": 0,
	"lore": "La seule à oser l'ascension. Son style dépend de l'arme qu'elle empoigne.",
}

# --- ARMES & COMPÉTENCES ------------------------------------------------------
# Chaque arme a un TYPE (mêlée / distance / magie) qui détermine :
#   • quelles COMPÉTENCES actives sont utilisables (cf. SKILLS, plus bas) ;
#   • une compétence PASSIVE (un proc, cf. UNIQUE_BASES) appliquée en continu.
# La compétence ACTIVE est possédée par l'héroïne (Entity.active_skill_id) : au
# départ c'est la base du type ; les autres se droppent. Recharge en TOURS.
const WEAPON_TYPES := ["melee", "ranged", "magic"]
const WEAPON_TYPE_NAME := { "melee": "Mêlée", "ranged": "Distance", "magic": "Magie" }
const WEAPON_TYPE_COLOR := {
	"melee": Color(1.0, 0.6, 0.4), "ranged": Color(0.6, 0.95, 0.6), "magic": Color(0.55, 0.7, 1.0),
}
# Compétence de BASE par type d'arme : possédée dès le loadout, améliorable plus
# tard via l'arbre de Connaissances (Phase 5). Les AUTRES compétences se droppent.
const WEAPON_TYPE_BASE_SKILL := { "melee": "cleave", "ranged": "precise_shot", "magic": "bolt" }

# Raretés de COMPÉTENCES (indépendantes des raretés d'armes) : poids de drop + teinte.
const SKILL_RARITIES := {
	"base":    { "name": "Base",    "color": Color(0.80, 0.80, 0.88), "weight": 0.0 },
	"commune": { "name": "Commune", "color": Color(0.78, 0.78, 0.82), "weight": 60.0 },
	"rare":    { "name": "Rare",    "color": Color(0.45, 0.70, 1.00), "weight": 28.0 },
	"epique":  { "name": "Épique",  "color": Color(0.78, 0.45, 1.00), "weight": 12.0 },
}

# Registre des COMPÉTENCES ACTIVES (data-driven). Chaque entrée :
#   wtype  : type d'arme requis (la compétence n'est utilisable qu'avec ce type)
#   rarity : rareté de compétence ("base" = de départ, non droppée)
#   cd     : recharge en TOURS ; range : portée en cases
#   effect : tag interprété par Main._cast_skill (réutilise les primitives Phase 1)
#   power  : multiplicateur de dégâts ; champs additionnels selon l'effet.
const SKILLS := {
	# === MÊLÉE ===
	"cleave":          { "name": "Tourbillon d'acier", "desc": "Frappe tous les ennemis adjacents.",            "wtype": "melee",  "rarity": "base",    "cd": 3, "range": 1, "effect": "aoe",         "radius": 1, "power": 1.0 },
	"double_strike":   { "name": "Frappe double",       "desc": "Deux coups rapides sur l'ennemi adjacent.",     "wtype": "melee",  "rarity": "commune", "cd": 2, "range": 1, "effect": "melee_multi", "hits": 2,   "power": 0.65 },
	"sunder":          { "name": "Brise-garde",         "desc": "Un coup qui ignore la défense.",                "wtype": "melee",  "rarity": "rare",    "cd": 3, "range": 1, "effect": "true_strike", "power": 1.4 },
	"vampiric_strike": { "name": "Lame vampirique",     "desc": "Frappe et te soigne de 50% des dégâts infligés.","wtype": "melee", "rarity": "rare",    "cd": 3, "range": 1, "effect": "vampiric",    "power": 1.1, "heal_pct": 0.5 },
	"cataclysm":       { "name": "Cataclysme",          "desc": "Énorme frappe de zone (rayon 2).",              "wtype": "melee",  "rarity": "epique",  "cd": 4, "range": 2, "effect": "aoe",         "radius": 2, "power": 1.3 },
	"dash_strike":     { "name": "Charge fendante",     "desc": "Bondit vers l'ennemi le plus proche et le frappe.","wtype": "melee","rarity": "rare",   "cd": 3, "range": 1, "effect": "dash_strike", "power": 1.2, "dash": 3 },
	"shield_bash":     { "name": "Coup de bélier",      "desc": "Frappe l'ennemi adjacent et le repousse de 2 cases (eau, lave, pièges et collisions font le reste).", "wtype": "melee", "rarity": "commune", "cd": 3, "range": 1, "effect": "push_strike", "power": 0.8, "push": 2 },
	# === DISTANCE ===
	"precise_shot":    { "name": "Tir précis",          "desc": "Décoche une flèche puissante à distance.",      "wtype": "ranged", "rarity": "base",    "cd": 2, "range": 5, "effect": "single",      "power": 1.0 },
	"double_shot":     { "name": "Tir double",          "desc": "Deux flèches sur la cible la plus proche.",     "wtype": "ranged", "rarity": "commune", "cd": 2, "range": 5, "effect": "ranged_multi","hits": 2,   "power": 0.65 },
	"explosive_shot":  { "name": "Tir explosif",        "desc": "La flèche explose autour de la cible (rayon 1).","wtype": "ranged","rarity": "rare",    "cd": 3, "range": 6, "effect": "explosive",   "radius": 1, "power": 1.0 },
	"piercing_shot":   { "name": "Tir transperçant",    "desc": "Traverse tous les ennemis alignés.",            "wtype": "ranged", "rarity": "rare",    "cd": 3, "range": 8, "effect": "pierce",      "power": 1.1 },
	"bouncing_shot":   { "name": "Tir rebondissant",    "desc": "Rebondit entre plusieurs ennemis.",             "wtype": "ranged", "rarity": "rare",    "cd": 3, "range": 6, "effect": "bounce",      "bounces": 3, "power": 0.9 },
	"crippling_shot":  { "name": "Tir entravant",       "desc": "Touche et ralentit la cible (3 tours).",        "wtype": "ranged", "rarity": "commune", "cd": 3, "range": 6, "effect": "status_shot", "status": "slow", "turns": 3, "val": 0.4, "power": 0.9 },
	# === MAGIE ===
	"bolt":            { "name": "Éclair foudroyant",   "desc": "Foudroie l'ennemi le plus proche. L'eau adjacente conduit la foudre aux autres ennemis du rivage.", "wtype": "magic",  "rarity": "base",    "cd": 3, "range": 6, "effect": "single",      "power": 1.0, "elem": "lightning" },
	"arc_bolt":        { "name": "Double éclair",       "desc": "Deux éclairs sur la cible la plus proche. L'eau adjacente conduit la foudre.", "wtype": "magic",  "rarity": "commune", "cd": 3, "range": 6, "effect": "ranged_multi","hits": 2,   "power": 0.65, "elem": "lightning" },
	"fireball":        { "name": "Boule de feu",        "desc": "Explose autour de la cible (rayon 1) et peut embraser les arbres alentour.", "wtype": "magic",  "rarity": "rare",    "cd": 4, "range": 6, "effect": "explosive",   "radius": 1, "power": 1.2, "elem": "fire" },
	"frost_nova":      { "name": "Éclat de givre",      "desc": "Touche et paralyse la cible (1 tour). Gèle l'eau voisine en un pont de glace temporaire.", "wtype": "magic",  "rarity": "epique",  "cd": 4, "range": 6, "effect": "status_shot", "status": "stun", "turns": 1, "power": 0.8, "elem": "frost" },
	"chain_lightning": { "name": "Chaîne d'éclairs",    "desc": "Rebondit en chaîne entre les ennemis. L'eau adjacente conduit la foudre.", "wtype": "magic",  "rarity": "rare",    "cd": 3, "range": 6, "effect": "chain",       "bounces": 3, "power": 0.9, "elem": "lightning" },
	"ember":           { "name": "Trait ardent",        "desc": "Touche et embrase la cible (brûlure, 3 tours) ainsi que les arbres voisins.","wtype": "magic",  "rarity": "commune", "cd": 3, "range": 6, "effect": "status_shot", "status": "burn", "turns": 3, "val": 0.3, "power": 0.8, "elem": "fire" },
}

static func skill_rarity_color(id: String) -> Color:
	var s: Dictionary = SKILLS.get(id, {})
	return SKILL_RARITIES.get(s.get("rarity", "commune"), SKILL_RARITIES["commune"])["color"]

# Armes de départ proposées au loadout (une par type). Items d'équipement
# complets (slot "arme", rareté Commun) ; le proc en fait la passive de l'arme.
const STARTER_WEAPONS := {
	"melee":  { "name": "Épée d'entraînement", "wtype": "melee",  "bonus": { "atk": 3 },             "proc": "frappe_double", "proc_val": 0.20 },
	"ranged": { "name": "Arc de chasse",       "wtype": "ranged", "bonus": { "atk": 2, "speed": 10 },"proc": "premier_coup",  "proc_val": 1.0 },
	"magic":  { "name": "Bâton d'apprenti",    "wtype": "magic",  "bonus": { "magic": 4 },           "proc": "frenesie",      "proc_val": 0.25 },
}

## Fabrique un objet-arme complet à partir d'une définition de STARTER_WEAPONS.
static func make_starter_weapon(wtype: String) -> Dictionary:
	var d: Dictionary = STARTER_WEAPONS[wtype]
	return {
		"kind": "equip", "name": d["name"], "slot": "arme", "sprite": "arme",
		"weapon_type": wtype,
		"rarity": "commun", "rarity_name": "Commun", "rarity_color": RARITIES[0]["color"],
		"bonus": d["bonus"].duplicate(true), "salvage": 3,
		"proc": d["proc"], "proc_val": d["proc_val"], "desc": _proc_desc(d["proc"], d["proc_val"]),
	}

# --- VISION / BROUILLARD DE GUERRE --------------------------------------------
# Rayon de vision initial du héros (en cases). Améliorable via les talents
# "Clairvoyance" / "Œil de Lynx" (mod "vision").
const BASE_VISION := 6

# --- PLAFONDS DE STATS DÉRIVÉES ------------------------------------------------
# Empêche le cumul d'artefacts/talents/affixes de rendre le héros invincible.
const CAP_DODGE := 0.60
const CAP_CRIT := 0.75
const CAP_LIFESTEAL := 0.50

# --- COURBES D'ÉCHELLE (Phase 5.2 : leviers d'équilibrage, data-driven) --------
# Pente d'échelle par étage appliquée aux stats ennemies dans Main._make_enemy.
# HP et ATK ont des pentes SÉPARÉES (avant Phase 5.2 elles partageaient 0.12) :
# on peut durcir les PV sans gonfler les dégâts, ou l'inverse. La Défense était
# NON scalée — elle l'est désormais (pente douce) pour que les tanks tardifs
# tiennent. Objectif : étage de mort médian sans méta ≈ 12-15.
const ENEMY_HP_SLOPE := 0.12
const ENEMY_ATK_SLOPE := 0.10
const ENEMY_DEF_SLOPE := 0.06
const BOSS_HP_SLOPE := 0.18
const BOSS_ATK_SLOPE := 0.15
const BOSS_DEF_SLOPE := 0.08
# Pente d'échelle des objets procéduraux (cf. _generate_procedural_item).
const ITEM_SCALE_SLOPE := 0.08

# --- TERRAIN ÉLÉMENTAIRE (Phase 4) ---------------------------------------------
# Chance par tour, par arbre adjacent à une case en feu, de s'embraser à son
# tour. `static var` (pas `const`) pour que le smoke test puisse la forcer à
# 1.0 et vérifier la propagation de façon déterministe.
static var FIRE_SPREAD_CHANCE := 0.35

# Foudre conduite par l'eau : part des dégâts du coup infligée aux AUTRES
# ennemis adjacents au même plan d'eau que la cible.
const LIGHTNING_CONDUCT_PCT := 0.5
# Gel : rayon (Chebyshev, autour de l'impact) des cases d'eau gelées, et durée
# (en actions de la joueuse) avant la fonte.
const FROST_FREEZE_RADIUS := 4
const FROZEN_TURNS := 10
# Nuages toxiques (marais) : durée et poison appliqué par tour aux entités dedans.
const CLOUD_TURNS := 3
const CLOUD_POISON_VAL := 3.0

# --- BIOMES (terrain "open world" par étage) ----------------------------------
# Le biome change tous les BIOME_SPAN étages et détermine la palette, la densité
# des éléments de terrain (arbres/rochers/eau/décor) et les sprites utilisés.
# Les sprites sont nommés "<id>_ground|_tree|_rock|_water|_decor" + "road"
# (générés par _assets_gen.gd, mappés par MapView.gd).
const BIOME_SPAN := 12

# --- TAILLE DE CARTE (procédurale, ré-échantillonnée à chaque étage) -----------
# Ratio largeur:hauteur = 1.6 (64x40, 320x200, 640x400 le respectent tous).
# Distribution triangulaire sur la hauteur : la carte la plus FRÉQUENTE est
# 320x200, tandis que la minuscule (64x40) et l'immense (640x400) sont rares.
const MAP_MIN_H := 40
const MAP_MAX_H := 400
const MAP_MODE_H := 200
const MAP_RATIO := 1.6

static func random_map_size(rng: RandomNumberGenerator) -> Vector2i:
	var h: int = int(round(_triangular(rng, float(MAP_MIN_H), float(MAP_MAX_H), float(MAP_MODE_H))))
	h = clampi(h, MAP_MIN_H, MAP_MAX_H)
	var w: int = clampi(int(round(h * MAP_RATIO)), 64, 640)
	return Vector2i(w, h)

# Distribution triangulaire (inverse de la CDF) : pic en `mode`, extrêmes rares.
static func _triangular(rng: RandomNumberGenerator, lo: float, hi: float, mode: float) -> float:
	var u: float = rng.randf()
	var c: float = (mode - lo) / (hi - lo)
	if u < c:
		return lo + sqrt(u * (hi - lo) * (mode - lo))
	return hi - sqrt((1.0 - u) * (hi - lo) * (hi - mode))

# Palettes refondues façon Moonring (med-fantasy néon) : sols TRÈS sombres et
# désaturés sur lesquels des accents néon (feuillage, eau, décor) ressortent
# nettement. Chaque biome garde son identité tout en partageant un undertone
# sombre unifié — pensé pour le pool de torche + la vignette de MapView.
const BIOMES := [
	{ "id": "plaine", "name": "Plaines verdoyantes",
	  "tree_density": 0.05, "rock_density": 0.03, "water_density": 0.04, "decor_density": 0.10, "road": true,
	  "ground_a": Color(0.090, 0.135, 0.100), "ground_b": Color(0.130, 0.190, 0.135),
	  "trunk": Color(0.30, 0.21, 0.13), "leaf": Color(0.36, 0.72, 0.40), "tree_style": "round",
	  "rock": Color(0.36, 0.40, 0.50), "water": Color(0.18, 0.55, 0.66),
	  "decor": Color(1.0, 0.83, 0.34), "decor_styles": ["flower", "tall_grass", "dandelion"],
	  "poi": { "structure": "standing_stone", "name": "Cercle de pierres druidique", "dressing": [0, 1] },
	  "ambient": { "color": Color(0.95, 0.78, 0.35), "count": 18, "vel": Vector2(14.0, -8.0), "size": 2 } },
	{ "id": "foret", "name": "Forêt profonde",
	  "tree_density": 0.14, "rock_density": 0.03, "water_density": 0.03, "decor_density": 0.10, "road": true,
	  "ground_a": Color(0.060, 0.120, 0.100), "ground_b": Color(0.095, 0.175, 0.135),
	  "trunk": Color(0.26, 0.17, 0.11), "leaf": Color(0.24, 0.66, 0.42), "tree_style": "pine",
	  "rock": Color(0.28, 0.37, 0.39), "water": Color(0.13, 0.46, 0.52),
	  "decor": Color(0.94, 0.27, 0.36), "decor_styles": ["mushroom", "fern", "spider_web"],
	  "poi": { "structure": "forest_altar", "name": "Autel sylvestre", "dressing": [0, 1] },
	  "ambient": { "color": Color(0.42, 0.70, 0.34), "count": 24, "vel": Vector2(4.0, 18.0), "size": 2 } },
	{ "id": "desert", "name": "Désert de cendres dorées",
	  "tree_density": 0.04, "rock_density": 0.06, "water_density": 0.01, "decor_density": 0.07, "road": true,
	  "ground_a": Color(0.205, 0.150, 0.085), "ground_b": Color(0.290, 0.215, 0.120),
	  "trunk": Color(0.32, 0.42, 0.24), "leaf": Color(0.42, 0.70, 0.34), "tree_style": "cactus",
	  "rock": Color(0.50, 0.40, 0.26), "water": Color(0.20, 0.64, 0.66),
	  "decor": Color(0.92, 0.88, 0.74), "decor_styles": ["bones", "tumbleweed", "cracked_earth"],
	  "poi": { "structure": "wagon_wheel", "name": "Caravane abandonnée", "dressing": [0, 1] },
	  "ambient": { "color": Color(0.86, 0.82, 0.68), "count": 16, "vel": Vector2(46.0, 2.0), "size": 1 } },
	{ "id": "toundra", "name": "Toundra gelée",
	  "tree_density": 0.07, "rock_density": 0.04, "water_density": 0.05, "decor_density": 0.08, "road": false,
	  "ground_a": Color(0.105, 0.140, 0.215), "ground_b": Color(0.150, 0.205, 0.300),
	  "trunk": Color(0.30, 0.26, 0.24), "leaf": Color(0.54, 0.78, 0.82), "tree_style": "pine",
	  "rock": Color(0.42, 0.50, 0.60), "water": Color(0.36, 0.74, 0.90),
	  "decor": Color(0.62, 0.90, 1.0), "decor_styles": ["crystal", "icicle", "snow_drift"],
	  "poi": { "structure": "ice_cairn", "name": "Cairn glacé", "dressing": [0, 1] },
	  "ambient": { "color": Color(0.92, 0.95, 1.0), "count": 40, "vel": Vector2(2.0, 12.0), "size": 1 } },
	{ "id": "marais", "name": "Marais putride",
	  "tree_density": 0.08, "rock_density": 0.03, "water_density": 0.14, "decor_density": 0.10, "road": false,
	  "ground_a": Color(0.100, 0.130, 0.090), "ground_b": Color(0.140, 0.180, 0.110),
	  "trunk": Color(0.20, 0.18, 0.13), "leaf": Color(0.36, 0.50, 0.24), "tree_style": "dead",
	  "rock": Color(0.28, 0.33, 0.29), "water": Color(0.22, 0.42, 0.27),
	  "decor": Color(0.64, 0.86, 0.32), "decor_styles": ["reed", "lily_pad", "wisp"],
	  "poi": { "structure": "sunken_ruin", "name": "Autel englouti", "dressing": [0, 1] },
	  "ambient": { "color": Color(0.55, 0.90, 0.35), "count": 14, "vel": Vector2(2.0, -2.0), "size": 2 } },
	{ "id": "volcan", "name": "Terres de feu",
	  "tree_density": 0.05, "rock_density": 0.08, "water_density": 0.06, "decor_density": 0.07, "road": false,
	  "ground_a": Color(0.105, 0.072, 0.090), "ground_b": Color(0.165, 0.100, 0.110),
	  "trunk": Color(0.16, 0.12, 0.12), "leaf": Color(0.24, 0.17, 0.17), "tree_style": "dead",
	  "rock": Color(0.28, 0.21, 0.23), "water": Color(1.0, 0.46, 0.16),
	  "decor": Color(1.0, 0.58, 0.20), "decor_styles": ["ember", "obsidian_shard", "ash_pile"],
	  "poi": { "structure": "abandoned_anvil", "name": "Forge abandonnée", "dressing": [0, 1] },
	  "ambient": { "color": Color(1.0, 0.55, 0.20), "count": 22, "vel": Vector2(3.0, -20.0), "size": 1 } },
]

## Renvoie le biome correspondant à un étage (change tous les BIOME_SPAN étages).
static func biome_for_floor(floor: int) -> Dictionary:
	var idx: int = int((max(1, floor) - 1) / BIOME_SPAN) % BIOMES.size()
	return BIOMES[idx]

static func biome_sprite(biome_id: String, role: String) -> String:
	return "%s_%s" % [biome_id, role]

## Nom du sprite pour la N-ième variante de décor du biome (0 = style historique
## "<id>_decor", 1 = "<id>_decor2", 2 = "<id>_decor3"...).
static func biome_decor_sprite(biome_id: String, variant: int) -> String:
	if variant <= 0:
		return "%s_decor" % biome_id
	return "%s_decor%d" % [biome_id, variant + 1]

# --- Décor du monde ouvert (props globaux, indépendants du biome) -------------
# Petits éléments d'ambiance posés sur le sol praticable, en plus du décor
# propre à chaque biome (fleurs/champignons/etc). Rares : c'est de la garniture,
# pas le décor principal.
const WORLD_PROPS := [
	{ "id": "campfire", "weight": 0.16 },
	{ "id": "crate", "weight": 0.20 },
	{ "id": "barrel", "weight": 0.18 },
	{ "id": "signpost", "weight": 0.12 },
	{ "id": "lantern_post", "weight": 0.16 },
]
const WORLD_PROPS_DENSITY := 0.010

# Obstacles infranchissables alternatifs aux rochers — apportent de la variété
# au terrain bloquant. Utilisés avec modération (faible probabilité par case
# de rocher) pour ne pas noyer le biome sous les props.
const OBSTACLE_VARIANTS := [
	{ "id": "fallen_log", "weight": 0.5 },
	{ "id": "ruins_pillar", "weight": 0.5 },
]
const OBSTACLE_VARIANT_CHANCE := 0.07

## Tire un élément pondéré dans une liste de {"id", "weight"} (RNG fourni).
static func weighted_pick(pool: Array, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for p in pool:
		total += float(p["weight"])
	var r: float = rng.randf() * total
	for p in pool:
		r -= float(p["weight"])
		if r <= 0.0:
			return p["id"]
	return pool[-1]["id"]

# --- ENNEMIS ------------------------------------------------------------------
const ENEMIES := [
	# Phase 5.2 : champ optionnel "max_floor" — l'espèce se retire de la sélection
	# au-delà de cet étage (les faibles cèdent la place au lieu de scaler à
	# l'infini). Champ optionnel "xp" (défaut = shards, cf. Main._make_enemy) pour
	# régler l'XP indépendamment de l'économie d'Éclats.
	{ "name": "Gobelin",  "glyph": "g", "sprite": "gobelin",   "color": Color(0.5, 0.8, 0.3), "max_hp": 8,  "atk": 3, "defense": 0, "speed": 100, "shards": 2, "min_floor": 1, "max_floor": 14 },
	{ "name": "Loup",     "glyph": "w", "sprite": "loup",      "color": Color(0.8, 0.8, 0.8), "max_hp": 10, "atk": 4, "defense": 0, "speed": 130, "shards": 3, "min_floor": 1, "max_floor": 16 },
	{ "name": "Squelette","glyph": "s", "sprite": "squelette", "color": Color(0.9, 0.9, 0.85),"max_hp": 14, "atk": 5, "defense": 2, "speed": 100, "shards": 4, "min_floor": 3 },
	{ "name": "Orc",      "glyph": "o", "sprite": "orc",       "color": Color(0.4, 0.7, 0.4), "max_hp": 20, "atk": 7, "defense": 3, "speed": 90,  "shards": 6, "min_floor": 5 },
	{ "name": "Spectre",  "glyph": "S", "sprite": "spectre",   "color": Color(0.7, 0.5, 1.0), "max_hp": 18, "atk": 9, "defense": 1, "speed": 115, "shards": 8, "min_floor": 7 },

	# --- Nouveaux monstres (data-driven : champ "ai" = comportement + traits) ---
	# Bêtes & créatures naturelles
	{ "name": "Araignée géante", "glyph": "a", "sprite": "araignee", "color": Color(0.55, 0.85, 0.45), "max_hp": 12, "atk": 4, "defense": 0, "speed": 110, "shards": 4, "min_floor": 2,
	  "ai": { "behavior": "melee", "on_hit": { "id": "poison", "turns": 3, "value": 3.0 }, "drops_trap": true } },
	{ "name": "Sanglier maudit", "glyph": "p", "sprite": "sanglier", "color": Color(0.55, 0.42, 0.35), "max_hp": 22, "atk": 6, "defense": 2, "speed": 120, "shards": 5, "min_floor": 3,
	  "ai": { "behavior": "charger", "resist_phys": 0.4 } },
	{ "name": "Chauve-souris vampire", "glyph": "v", "sprite": "chauvesouris", "color": Color(0.7, 0.4, 0.6), "max_hp": 9, "atk": 4, "defense": 0, "speed": 150, "shards": 4, "min_floor": 2,
	  "ai": { "behavior": "melee", "lifesteal": 0.6 } },
	{ "name": "Serpent des marais", "glyph": "n", "sprite": "serpent", "color": Color(0.4, 0.7, 0.4), "max_hp": 12, "atk": 3, "defense": 0, "speed": 140, "shards": 5, "min_floor": 4,
	  "ai": { "behavior": "melee", "atk_count": 2, "on_hit": { "id": "bleed", "turns": 3, "value": 3.0 }, "death_cloud": 0.3 } },
	{ "name": "Ours corrompu", "glyph": "U", "sprite": "ours", "color": Color(0.45, 0.35, 0.3), "max_hp": 34, "atk": 7, "defense": 2, "speed": 90, "shards": 8, "min_floor": 6,
	  "ai": { "behavior": "melee", "berserk": true, "berserk_at": 0.4, "berserk_mult": 1.6 } },

	# Morts-vivants & spectral
	{ "name": "Zombie pestilentiel", "glyph": "z", "sprite": "zombie", "color": Color(0.5, 0.65, 0.4), "max_hp": 22, "atk": 5, "defense": 1, "speed": 70, "shards": 5, "min_floor": 4,
	  "ai": { "behavior": "melee", "disease_aura": true, "on_hit": { "id": "disease", "turns": 4, "value": 3.0 }, "death_cloud": 0.3 } },
	{ "name": "Chevalier sans tête", "glyph": "D", "sprite": "dullahan", "color": Color(0.7, 0.72, 0.82), "max_hp": 40, "atk": 9, "defense": 3, "speed": 100, "shards": 14, "min_floor": 8,
	  "ai": { "behavior": "ranged", "ranged_range": 4, "cooldown": 1, "on_hit": { "id": "bleed", "turns": 2, "value": 3.0 } } },
	{ "name": "Liche", "glyph": "L", "sprite": "liche", "color": Color(0.6, 0.45, 0.95), "max_hp": 26, "atk": 6, "defense": 1, "speed": 100, "shards": 12, "min_floor": 9,
	  "ai": { "behavior": "caster", "cast": "summon", "summon": "squelette", "summon_max": 4, "cast_range": 7, "cooldown": 3, "kite_at": 4 } },
	{ "name": "Banshee", "glyph": "h", "sprite": "banshee", "color": Color(0.65, 0.8, 0.95), "max_hp": 20, "atk": 6, "defense": 0, "speed": 120, "shards": 10, "min_floor": 8,
	  "ai": { "behavior": "caster", "cast": "scream", "cast_range": 6, "cooldown": 4, "stun_turns": 1, "weaken_turns": 4, "weaken_val": 3.0, "kite_at": 3 } },
	{ "name": "Revenant", "glyph": "r", "sprite": "revenant", "color": Color(0.6, 0.6, 0.7), "max_hp": 22, "atk": 6, "defense": 1, "speed": 105, "shards": 9, "min_floor": 7,
	  "ai": { "behavior": "melee", "copy_player": true, "copy_ratio": 0.85 } },

	# Humanoïdes & factions
	{ "name": "Brigand maudit", "glyph": "b", "sprite": "brigand", "color": Color(0.7, 0.55, 0.4), "max_hp": 16, "atk": 6, "defense": 1, "speed": 110, "shards": 6, "min_floor": 5,
	  "ai": { "behavior": "ranged", "ranged_range": 4, "cooldown": 2, "drops_trap": true, "on_hit": { "id": "bleed", "turns": 2, "value": 2.0 } } },
	{ "name": "Gnoll", "glyph": "G", "sprite": "gnoll", "color": Color(0.7, 0.6, 0.35), "max_hp": 16, "atk": 5, "defense": 1, "speed": 115, "shards": 5, "min_floor": 4,
	  "ai": { "behavior": "melee", "pack": true, "pack_bonus": 2 } },
	{ "name": "Troll des cavernes", "glyph": "T", "sprite": "troll", "color": Color(0.45, 0.6, 0.45), "max_hp": 40, "atk": 7, "defense": 2, "speed": 85, "shards": 9, "min_floor": 7, "hp_regen": 4,
	  "ai": { "behavior": "melee", "weak_fire": 1.0 } },
	{ "name": "Kobold", "glyph": "k", "sprite": "kobold", "color": Color(0.8, 0.5, 0.35), "max_hp": 7, "atk": 3, "defense": 0, "speed": 125, "shards": 3, "min_floor": 2, "max_floor": 14,
	  "ai": { "behavior": "fleer", "pack": true, "pack_bonus": 1, "drops_trap": true } },
	{ "name": "Cultiste", "glyph": "c", "sprite": "cultiste", "color": Color(0.75, 0.4, 0.5), "max_hp": 18, "atk": 5, "defense": 0, "speed": 100, "shards": 8, "min_floor": 6,
	  "ai": { "behavior": "caster", "cast": "summon", "summon": "kobold", "summon_max": 3, "cast_range": 6, "cooldown": 3, "sacrifice": true, "sac_radius": 2, "sac_mult": 1.6, "kite_at": 3 } },

	# Élémentaires & magiques
	{ "name": "Élémentaire de feu", "glyph": "f", "sprite": "elementaire_feu", "color": Color(1.0, 0.55, 0.25), "max_hp": 20, "atk": 8, "defense": 1, "speed": 105, "shards": 10, "min_floor": 8,
	  "ai": { "behavior": "melee", "immune_fire": true, "on_hit": { "id": "burn", "turns": 3, "value": 3.0 }, "explode": { "radius": 2, "mult": 1.4 } } },
	{ "name": "Golem de pierre", "glyph": "O", "sprite": "golem", "color": Color(0.6, 0.6, 0.66), "max_hp": 55, "atk": 8, "defense": 5, "speed": 60, "shards": 14, "min_floor": 9,
	  "ai": { "behavior": "melee", "resist_phys": 0.6, "resist_magic": -0.6 } },
	{ "name": "Fée corrompue", "glyph": "y", "sprite": "fee", "color": Color(0.8, 0.6, 1.0), "max_hp": 12, "atk": 5, "defense": 0, "speed": 140, "shards": 8, "min_floor": 6,
	  "ai": { "behavior": "teleporter", "teleport_chance": 0.7, "teleport_range": 4, "on_hit": { "id": "confusion", "turns": 3, "value": 0.0 } } },
	{ "name": "Drake", "glyph": "K", "sprite": "drake", "color": Color(0.8, 0.5, 0.4), "max_hp": 30, "atk": 9, "defense": 2, "speed": 110, "shards": 12, "min_floor": 10,
	  "ai": { "behavior": "ranged", "ranged_range": 5, "cooldown": 2, "elemental": true } },
	{ "name": "Mimic", "glyph": "m", "sprite": "mimic", "color": Color(0.8, 0.6, 0.3), "max_hp": 24, "atk": 8, "defense": 2, "speed": 100, "shards": 12, "min_floor": 5,
	  "ai": { "behavior": "ambush" } },
]

const BOSS := {
	"name": "Gardien de l'Étage", "glyph": "B", "sprite": "boss", "color": Color(1.0, 0.3, 0.3),
	"max_hp": 60, "atk": 10, "defense": 4, "speed": 100, "shards": 40, "min_floor": 1,
}

# --- BOSS DE STRATE (data-driven, mécaniques signature via "ai") ----------------
# Un boss par strate ; sélection cyclique selon l'index de strate (cf.
# Main._pick_boss_def). Le Dieu-Bête (index 9) est le capstone de cycle.
# Clés ai spécifiques aux boss : guardians {count,sprite,resist} (gardiens liés
# qui protègent le boss tant qu'ils vivent), spawn_on_hit/soh_max (pond à chaque
# coup reçu), phases (change de comportement selon les PV).
const BOSSES := [
	{ "name": "Le Roi Liche Éternel", "glyph": "B", "sprite": "roi_liche", "color": Color(0.7, 0.55, 1.0),
	  "max_hp": 64, "atk": 10, "defense": 3, "speed": 100, "shards": 45, "min_floor": 1, "hp_regen": 5,
	  "ai": { "behavior": "caster", "cast": "summon", "summon": "squelette", "summon_max": 6, "cast_range": 9, "cooldown": 2, "kite_at": 3 } },
	{ "name": "Le Seigneur Fantôme", "glyph": "B", "sprite": "seigneur_fantome", "color": Color(0.6, 0.85, 1.0),
	  "max_hp": 60, "atk": 11, "defense": 2, "speed": 110, "shards": 48, "min_floor": 1,
	  "ai": { "behavior": "melee", "guardians": { "count": 3, "sprite": "ame", "resist": 0.9 } } },
	{ "name": "Le Drake Ancien", "glyph": "B", "sprite": "wyrm", "color": Color(0.7, 0.5, 0.4),
	  "max_hp": 78, "atk": 11, "defense": 4, "speed": 100, "shards": 50, "min_floor": 1,
	  "ai": { "behavior": "ranged", "ranged_range": 6, "cooldown": 1, "resist_phys": 0.2, "on_hit": { "id": "weaken", "turns": 3, "value": 4.0 } } },
	{ "name": "L'Araignée Mère", "glyph": "B", "sprite": "araignee_mere", "color": Color(0.55, 0.8, 0.45),
	  "max_hp": 70, "atk": 9, "defense": 2, "speed": 100, "shards": 50, "min_floor": 1,
	  "ai": { "behavior": "melee", "spawn_on_hit": "araignee", "soh_max": 8, "on_hit": { "id": "poison", "turns": 3, "value": 4.0 } } },
	{ "name": "Le Troll Ancestral", "glyph": "B", "sprite": "troll_ancestral", "color": Color(0.45, 0.62, 0.45),
	  "max_hp": 90, "atk": 11, "defense": 4, "speed": 90, "shards": 52, "min_floor": 1, "hp_regen": 8,
	  "ai": { "behavior": "melee", "weak_fire": 1.2 } },
	{ "name": "Le Paladin Déchu", "glyph": "B", "sprite": "paladin_dechu", "color": Color(0.85, 0.8, 0.6),
	  "max_hp": 72, "atk": 10, "defense": 5, "speed": 105, "shards": 52, "min_floor": 1,
	  "ai": { "behavior": "melee", "copy_player": true, "copy_ratio": 1.0, "resist_phys": 0.2 } },
	{ "name": "La Sorcière des Marais", "glyph": "B", "sprite": "sorciere", "color": Color(0.6, 0.75, 0.45),
	  "max_hp": 66, "atk": 10, "defense": 2, "speed": 100, "shards": 52, "min_floor": 1,
	  "ai": { "behavior": "caster", "cast": "summon", "summon": "serpent", "summon_max": 4, "cast_range": 7, "cooldown": 3, "kite_at": 3,
	          "guardians": { "count": 3, "sprite": "chaudron", "resist": 0.5 } } },
	{ "name": "Le Bourreau du Roi", "glyph": "B", "sprite": "bourreau", "color": Color(0.8, 0.3, 0.3),
	  "max_hp": 96, "atk": 16, "defense": 4, "speed": 70, "shards": 55, "min_floor": 1,
	  "ai": { "behavior": "charger", "push": 2, "on_hit": { "id": "bleed", "turns": 3, "value": 5.0 } } },
	{ "name": "L'Œil du Néant", "glyph": "B", "sprite": "oeil_neant", "color": Color(0.7, 0.5, 0.95),
	  "max_hp": 74, "atk": 12, "defense": 3, "speed": 100, "shards": 55, "min_floor": 1,
	  "ai": { "behavior": "ranged", "ranged_range": 7, "cooldown": 1, "resist_phys": 0.3, "on_hit": { "id": "slow", "turns": 2, "value": 0.5 } } },
	{ "name": "Le Dieu-Bête Corrompu", "glyph": "B", "sprite": "dieu_bete", "color": Color(0.9, 0.4, 0.5),
	  "max_hp": 120, "atk": 13, "defense": 4, "speed": 105, "shards": 80, "min_floor": 1, "hp_regen": 4,
	  "ai": { "behavior": "ranged", "phases": true, "ranged_range": 6, "cooldown": 1, "summon": "loup", "summon_max": 4, "cast": "summon",
	          "on_hit": { "id": "burn", "turns": 3, "value": 4.0 } } },
]

# --- AFFIXES D'ÉLITE (Phase 6.2) ----------------------------------------------
# Un affixe tiré par salle d'élite (remplace l'éponge ×1.25 plate) : donne un
# comportement, pas juste des stats. "tint" = teinte de rendu (modulate MapView).
const ELITE_AFFIXES := [
	{ "id": "rapide",     "name": "Rapide",     "tint": Color(0.40, 0.90, 1.00) },
	{ "id": "explosif",   "name": "Explosif",   "tint": Color(1.00, 0.55, 0.25) },
	{ "id": "regenerant", "name": "Régénérant", "tint": Color(0.45, 0.90, 0.50) },
	{ "id": "voleur",     "name": "Voleur",     "tint": Color(1.00, 0.82, 0.35) },
	{ "id": "chef",       "name": "Chef",       "tint": Color(1.00, 0.40, 0.40) },
]

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
	{ "name": "Dague",    "slot": "arme",    "primary": { "atk": 1, "speed": 8 }, "wtype": "melee" },
	{ "name": "Épée",     "slot": "arme",    "primary": { "atk": 3 },            "wtype": "melee" },
	{ "name": "Hache",    "slot": "arme",    "primary": { "atk": 5, "speed": -5 },"wtype": "melee" },
	{ "name": "Arc",      "slot": "arme",    "primary": { "atk": 2, "speed": 6 }, "wtype": "ranged" },
	{ "name": "Bâton",    "slot": "arme",    "primary": { "magic": 4 },          "wtype": "magic" },
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

# --- PRÉFIXES DE COMBAT (inspiré de Dungeonmans) ------------------------------
# Contrairement aux AFFIXES ci-dessus (bonus de stat plats), un préfixe ajoute
# un EFFET DE COMBAT à un objet procédural (Commun/Rare) — tiré indépendamment
# des affixes de stat, réservé à un slot (arme = déclenché à l'attaque, armure
# = déclenché en défense). Un seul scalaire par préfixe (magnitude OU chance
# selon l'effet), dans l'esprit "un proc = une valeur" du reste du code
# (cf. UNIQUE_BASES/proc_val). Épique/Légendaire gardent leur identité propre
# (bibliothèque d'objets nommés) et ne tirent pas de préfixe en plus.
const PREFIXES := [
	{ "id": "ardent",     "name": "du Brasier",       "slot": "arme",
	  "base": 3.0, "per_floor": 0.12, "max": 9.0 },
	{ "id": "givre",      "name": "du Givre",         "slot": "arme",
	  "base": 0.25, "per_floor": 0.0, "max": 0.25 },
	{ "id": "venimeux",   "name": "du Venin",         "slot": "arme",
	  "base": 0.30, "per_floor": 0.0, "max": 0.30 },
	{ "id": "foudroyant", "name": "de la Foudre",     "slot": "arme",
	  "base": 0.12, "per_floor": 0.0, "max": 0.12 },
	{ "id": "cuirasse",   "name": "du Rempart",       "slot": "armure",
	  "base": 2.0, "per_floor": 0.08, "max": 6.0 },
	{ "id": "renvoi",     "name": "des Représailles", "slot": "armure",
	  "base": 0.25, "per_floor": 0.0, "max": 0.25 },
]
# Chance qu'un objet procédural tire un préfixe, par rareté (Épique/Légendaire
# gardent leur propre effet et n'en tirent pas). Rare a plus de chances que
# Commun : c'est la rareté qui doit sembler "spéciale" sans égaler l'Épique.
const PREFIX_CHANCE := { "commun": 0.12, "rare": 0.22 }

## Tire un préfixe compatible avec le slot donné (dict vide si aucun tiré).
static func _roll_prefix(slot: String, rarity_id: String, floor: int, rng: RandomNumberGenerator) -> Dictionary:
	var chance: float = float(PREFIX_CHANCE.get(rarity_id, 0.0))
	if chance <= 0.0 or rng.randf() >= chance:
		return {}
	var pool: Array = []
	for p in PREFIXES:
		if p["slot"] == slot:
			pool.append(p)
	if pool.is_empty():
		return {}
	var def: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	var value: float = minf(float(def["max"]), float(def["base"]) + float(def["per_floor"]) * float(floor - 1))
	return { "id": def["id"], "name": String(def["name"]), "value": value }

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
	# --- ARME (17) --- wtype explicite (Arc = ranged ; Bâton/Sceptre = magic ; reste melee)
	{ "name": "Lame des Damnés",      "slot": "arme", "wtype": "melee",  "stat": { "atk": 6 },                "proc": "execution",     "val": 0.50 },
	{ "name": "Hache du Bourreau",    "slot": "arme", "wtype": "melee",  "stat": { "atk": 8, "speed": -4 },    "proc": "frenesie",      "val": 0.30 },
	{ "name": "Dague du Silence",     "slot": "arme", "wtype": "melee",  "stat": { "atk": 3, "speed": 10 },    "proc": "premier_coup",  "val": 1.0 },
	{ "name": "Marteau du Tyran",     "slot": "arme", "wtype": "melee",  "stat": { "atk": 9, "defense": 1 },   "proc": "frappe_double", "val": 0.25 },
	{ "name": "Croc Ancestral",       "slot": "arme", "wtype": "melee",  "stat": { "atk": 5 },                 "proc": "soif_de_sang",  "val": 0.12 },
	{ "name": "Faux du Faucheur",     "slot": "arme", "wtype": "melee",  "stat": { "atk": 7 },                 "proc": "moisson",       "val": 4.0 },
	{ "name": "Épée du Sacrifice",    "slot": "arme", "wtype": "melee",  "stat": { "atk": 8, "max_hp": -6 },   "proc": "execution",     "val": 0.65 },
	{ "name": "Bâton des Cendres",    "slot": "arme", "wtype": "magic",  "stat": { "magic": 6 },               "proc": "frenesie",      "val": 0.35 },
	{ "name": "Arc du Vent",          "slot": "arme", "wtype": "ranged", "stat": { "atk": 4, "speed": 12 },    "proc": "premier_coup",  "val": 1.0 },
	{ "name": "Sceptre Runique",      "slot": "arme", "wtype": "magic",  "stat": { "magic": 7, "defense": 1 }, "proc": "frappe_double", "val": 0.22 },
	{ "name": "Lame Jumelle",         "slot": "arme", "wtype": "melee",  "stat": { "atk": 5, "speed": 6 },     "proc": "soif_de_sang",  "val": 0.14 },
	{ "name": "Hallebarde de Garde",  "slot": "arme", "wtype": "melee",  "stat": { "atk": 6, "defense": 2 },   "proc": "moisson",       "val": 5.0 },
	{ "name": "Poignard Vicieux",     "slot": "arme", "wtype": "melee",  "stat": { "atk": 4 },                 "proc": "execution",     "val": 0.55 },
	{ "name": "Fléau Sacré",          "slot": "arme", "wtype": "melee",  "stat": { "atk": 7, "magic": 2 },     "proc": "frenesie",      "val": 0.30 },
	{ "name": "Bâton du Sage Fou",    "slot": "arme", "wtype": "magic",  "stat": { "magic": 8, "speed": -3 },  "proc": "premier_coup",  "val": 1.0 },
	{ "name": "Lame Spectrale",       "slot": "arme", "wtype": "melee",  "stat": { "atk": 5, "speed": 8 },     "proc": "frappe_double", "val": 0.28 },
	{ "name": "Glaive du Crépuscule", "slot": "arme", "wtype": "melee",  "stat": { "atk": 8 },                 "proc": "moisson",       "val": 4.0 },
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
		"ardent": return "Brasier : inflige %d à %d dégâts de feu bonus par attaque et peut embraser un arbre voisin." % [maxi(1, int(val) - 1), int(val) + 1]
		"givre": return "Givre : %d%% de chances de ralentir la cible touchée et de geler l'eau à son contact." % int(round(val * 100))
		"venimeux": return "Venin : %d%% de chances d'empoisonner la cible touchée." % int(round(val * 100))
		"foudroyant": return "Foudre : %d%% de chances d'étourdir la cible touchée (1 tour)." % int(round(val * 100))
		"cuirasse": return "Rempart : réduit chaque coup subi de %d dégâts." % int(round(val))
		"renvoi": return "Représailles : %d%% de chances d'affaiblir un attaquant au contact." % int(round(val * 100))
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
	var item: Dictionary = {
		"kind": "equip", "name": uniq["name"], "slot": slot, "unique": true,
		"rarity": rarity["id"], "rarity_name": rarity["name"], "rarity_color": rarity["color"],
		"bonus": ubonus, "salvage": int(rarity["salvage"]) + floor, "sprite": slot,
		"proc": uniq["proc"], "proc_val": uniq["proc_val"], "desc": uniq["desc"],
	}
	if slot == "arme":
		item["weapon_type"] = String(uniq.get("wtype", "melee"))
	return item

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
	var fscale: float = 1.0 + float(floor - 1) * ITEM_SCALE_SLOPE
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
	var prefix: Dictionary = _roll_prefix(slot, rarity["id"], floor, rng)
	if not prefix.is_empty():
		name += " " + String(prefix["name"])
	var item: Dictionary = {
		"kind": "equip", "name": name, "slot": slot,
		"rarity": rarity["id"], "rarity_name": rarity["name"], "rarity_color": rarity["color"],
		"bonus": bonus, "salvage": int(rarity["salvage"]) + floor, "sprite": slot,
	}
	if not prefix.is_empty():
		item["proc"] = prefix["id"]
		item["proc_val"] = prefix["value"]
		item["desc"] = _proc_desc(prefix["id"], prefix["value"])
	if slot == "arme":
		item["weapon_type"] = String(base.get("wtype", "melee"))
	return item

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
# Deux familles : talents de STAT plate (champ "mods", appliqués par
# Entity.recompute_stats) et talents MÉCANIQUES (Phase 6.1, champ "hook" lu à un
# site de jeu explicite via Entity.has_talent_hook — ils changent une règle,
# pas un chiffre). Chasseur nocturne porte les deux (mods vision + hook dégâts).
const TALENTS := [
	{ "id": "vigueur",   "name": "Vigueur",       "desc": "+12 PV max",                 "mods": { "max_hp": 12 } },
	{ "id": "puissance", "name": "Puissance",     "desc": "+2 Attaque",                 "mods": { "atk": 2 } },
	{ "id": "carapace",  "name": "Carapace",      "desc": "+2 Défense",                 "mods": { "defense": 2 } },
	{ "id": "celerite",  "name": "Célérité",      "desc": "+15 Vitesse",                "mods": { "speed": 15 } },
	{ "id": "precision", "name": "Précision",     "desc": "+10% Coup critique",         "mods": { "crit_chance": 0.10 } },
	{ "id": "agilite",   "name": "Agilité",       "desc": "+10% Esquive",               "mods": { "dodge_chance": 0.10 } },
	{ "id": "phenix",    "name": "Second souffle","desc": "+1 résurrection (50% PV)",   "mods": { "max_revives": 1 } },
	{ "id": "clairvoyance", "name": "Clairvoyance", "desc": "+1 rayon de vision",        "mods": { "vision": 1 } },
	# --- Talents mécaniques (hooks) ---
	{ "id": "pyromane",  "name": "Pyromane",      "desc": "Tes ignitions se propagent à 50% et tes brûlures montent d'un palier de plus.", "hook": "pyromane" },
	{ "id": "balistique","name": "Balistique",    "desc": "+1 rebond et +2 de portée de transpercement.", "hook": "balistique" },
	{ "id": "toxicologue","name": "Toxicologue",  "desc": "Tes poisons infligent 60% de dégâts en plus.", "hook": "toxicologue" },
	{ "id": "echo_arcanique","name": "Écho arcanique","desc": "15% de chances de ne pas consommer la recharge de ta capacité.", "hook": "echo_arcanique" },
	{ "id": "pied_leger","name": "Pied léger",    "desc": "Les pièges ne se déclenchent plus sous tes pas et sont repérés hors vision.", "hook": "pied_leger" },
	{ "id": "berserker", "name": "Berserker",     "desc": "+25% de dégâts tant que tu subis un poison, une brûlure ou un saignement.", "hook": "berserker" },
	{ "id": "chasseur_nuit","name": "Chasseur nocturne","desc": "+2 Vision et +10% de dégâts à distance ≥ 4.", "mods": { "vision": 2 }, "hook": "chasseur_nuit" },
	{ "id": "demolisseur","name": "Démolisseur",  "desc": "Tes poussées gagnent +1 case et infligent +3 dégâts.", "hook": "demolisseur" },
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

# --- POUVOIRS (Phase 3, drops rares, scope = run) -----------------------------
# Cumul illimité (pas de slot), sauf exclusions mutuelles explicites ("excludes").
# Sources : monstres légendaires (rares), Gardien tous les 15 étages, boutique.
const POWER_GLYPH := "Ω"
const POWERS := [
	{ "id": "drone", "name": "Drone d'assaut", "color": Color(0.55, 0.85, 1.0), "excludes": [],
	  "desc": "Un drone tire automatiquement sur l'ennemi le plus proche (portée 6) à chaque tour." },
	{ "id": "turret", "name": "Tourelle spectrale", "color": Color(0.85, 0.65, 0.35), "excludes": ["coeur_de_verre"],
	  "desc": "Une tourelle frappe en zone (rayon 1) l'ennemi le plus proche à chaque tour." },
	{ "id": "coeur_de_verre", "name": "Cœur de Verre", "color": Color(0.95, 0.75, 0.95), "excludes": ["turret"],
	  "desc": "+50% Attaque et +20% Critique, mais -30% PV max. Tout repose sur l'offensive." },
	{ "id": "detonation", "name": "Pacte de Détonation", "color": Color(1.0, 0.45, 0.25), "excludes": [],
	  "desc": "Chaque ennemi tué près de toi explose, infligeant des dégâts en zone aux alentours." },
	{ "id": "venin", "name": "Glande à Venin", "color": Color(0.55, 0.9, 0.4), "excludes": [],
	  "desc": "Chacune de tes attaques empoisonne sa cible." },
]

# Effets des pouvoirs exprimables en modificateurs de stats simples.
const POWER_MODS := {
	"coeur_de_verre": { "atk_pct": 0.50, "crit_chance": 0.20, "max_hp_pct": -0.30 },
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

# --- ARBRE DE CONNAISSANCES (Phase 5, 2ᵉ monnaie méta) ------------------------
# Les Connaissances ne s'achètent PAS en stats : chaque nœud débloque un SYSTÈME,
# une RÈGLE ou une OPTION qui change la façon de jouer (inspiré des arbres
# d'Integrated Strategies d'Arknights). Graphe à prérequis (DAG).
const KNOWLEDGE_BRANCHES := {
	"arsenal": { "name": "Voie de l'Arsenal", "color": Color(0.95, 0.6, 0.35) },
	"serment": { "name": "Voie du Serment",   "color": Color(0.85, 0.4, 0.45) },
	"savoir":  { "name": "Voie du Savoir",    "color": Color(0.55, 0.8, 1.0) },
}
const KNOWLEDGE_NODES := {
	# Voie de l'Arsenal — élargit le build et la variété de drops.
	"pacte_pouvoir": { "name": "Pacte de Pouvoir", "branch": "arsenal", "cost": 4, "requires": [],
		"desc": "Tu démarres chaque run avec un pouvoir passif aléatoire déjà actif." },
	"affinite": { "name": "Affinité Arcane", "branch": "arsenal", "cost": 6, "requires": ["pacte_pouvoir"],
		"desc": "Les compétences droppées sont tirées dans un meilleur pool de rareté." },
	"arsenal": { "name": "Arsenal Étendu", "branch": "arsenal", "cost": 5, "requires": ["pacte_pouvoir"],
		"desc": "La boutique propose toujours un pouvoir à l'achat." },
	# Voie du Serment — risque/récompense (cœur IS).
	"serments": { "name": "Serments", "branch": "serment", "cost": 3, "requires": [],
		"desc": "Débloque les Serments : modificateurs de difficulté optionnels au départ d'un run, qui augmentent tes gains." },
	"serment_majeur": { "name": "Serments Majeurs", "branch": "serment", "cost": 6, "requires": ["serments"],
		"desc": "Débloque des Serments plus durs et bien plus rémunérateurs." },
	"chasseur": { "name": "Chasseur de Légendes", "branch": "serment", "cost": 5, "requires": ["serments"],
		"desc": "Les monstres légendaires (porteurs de pouvoirs) apparaissent bien plus souvent." },
	# Voie du Savoir — exploration, collection et économie de Connaissances.
	"codex": { "name": "Codex", "branch": "savoir", "cost": 3, "requires": [],
		"desc": "Débloque le Codex consultable. Chaque découverte inédite (compétence, pouvoir, objet unique) rapporte +1 Connaissance." },
	"oeil_du_devin": { "name": "Œil du Devin", "branch": "savoir", "cost": 5, "requires": ["codex"],
		"desc": "Au début de chaque étage, le butin est révélé à travers le brouillard de guerre." },
	"forge": { "name": "Forge Itinérante", "branch": "savoir", "cost": 6, "requires": ["codex"],
		"desc": "Les nœuds Repos gagnent un 3ᵉ choix : forger une pièce d'équipement (bonus renforcé)." },
}
const KNOWLEDGE_ORDER := ["pacte_pouvoir", "affinite", "arsenal", "serments", "serment_majeur", "chasseur",
	"codex", "oeil_du_devin", "forge"]

# --- SERMENTS (modificateurs de difficulté optionnels, débloqués par l'arbre) --
# reward = bonus additif aux Éclats du run ; knowledge = Connaissances en plus.
const OATHS := [
	{ "id": "fragilite", "name": "Serment de Fragilité", "major": false, "reward": 0.15, "knowledge": 0,
	  "desc": "−25% PV max ce run.  Récompense : +15% Éclats." },
	{ "id": "pauvrete", "name": "Serment de Pauvreté", "major": false, "reward": 0.20, "knowledge": 0,
	  "desc": "Aucun bonus de départ (Fortune/Héritage/Instinct ignorés).  +20% Éclats." },
	{ "id": "horde", "name": "Serment de la Horde", "major": false, "reward": 0.20, "knowledge": 1,
	  "desc": "+50% d'ennemis par étage.  +20% Éclats, +1 Connaissance." },
	{ "id": "elite", "name": "Serment d'Élite", "major": true, "reward": 0.30, "knowledge": 1,
	  "desc": "Tous les combats sont des salles d'élite.  +30% Éclats, +1 Connaissance." },
	{ "id": "glas", "name": "Serment du Glas", "major": true, "reward": 0.25, "knowledge": 0,
	  "desc": "Le Gardien entre en rage dès 80% PV.  +25% Éclats." },
	{ "id": "funeste", "name": "Serment Funeste", "major": true, "reward": 0.25, "knowledge": 2,
	  "desc": "Plus aucun soin entre les étages.  +25% Éclats, +2 Connaissances." },
]

static func oath_by_id(id: String) -> Dictionary:
	for o in OATHS:
		if o["id"] == id:
			return o
	return {}

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
