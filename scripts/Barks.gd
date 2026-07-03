## Répliques d'Aria (Phase 6.7). Données pures : des pools de phrases (une ligne
## chacune) indexés par déclencheur. Main.bark() en tire une, l'affiche en
## journal + flottant, avec limitation de cadence. TOUJOURS une seule ligne.
class_name Barks
extends RefCounted

const COLOR := Color(0.85, 0.92, 1.0)

# Pools génériques par déclencheur.
const LOW_HP := [
	"Ça… ça va encore.",
	"Je tiens. Je dois tenir.",
	"Encore un souffle.",
]
const BOSS_KILL := [
	"Une strate de moins.",
	"La voie s'ouvre.",
	"Tu n'étais qu'un gardien.",
]
const ECHO_SEEN := [
	"Ce visage… c'est le mien.",
	"Encore moi ? Jusqu'où ?",
]

# Entrée de biome : pool par id de biome.
const BIOME_ENTER := {
	"plaine":  ["L'air est presque calme, ici.", "De l'herbe. Ça change."],
	"foret":   ["Ces arbres murmurent.", "Reste sur tes gardes sous les branches."],
	"desert":  ["La cendre brûle jusqu'aux poumons.", "Rien ne pousse ici. Rien."],
	"toundra": ["Le froid mord jusqu'à l'os.", "Mes pas crissent trop fort."],
	"marais":  ["Ça pue la mort et la vase.", "Chaque pas s'enfonce."],
	"volcan":  ["La roche saigne du feu.", "Le sol lui-même veut ma peau."],
}

# Intro de boss : pool par sprite puis par nombre de rencontres (0 / 1 / 2+).
const BOSS_INTRO := {
	"_default": {
		"0": ["Alors c'est toi, le gardien.", "Montre-moi ta strate."],
		"1": ["Encore toi. Je me souviens.", "On remet ça ?"],
		"2": ["Combien de fois faudra-t-il ?", "Tu ne me retiendras pas cette fois."],
	},
}

## Tire une réplique du pool, ou "" si vide. `rng` : RandomNumberGenerator unifié.
static func pick(pool: Array, rng: RandomNumberGenerator) -> String:
	if pool.is_empty():
		return ""
	return String(pool[rng.randi_range(0, pool.size() - 1)])

## Réplique d'intro de boss selon le sprite et le nombre de rencontres passées.
static func boss_intro(sprite: String, times_faced: int, rng: RandomNumberGenerator) -> String:
	var by_sprite: Dictionary = BOSS_INTRO.get(sprite, BOSS_INTRO["_default"])
	var tier: String = "2" if times_faced >= 2 else str(maxi(0, times_faced))
	return pick(by_sprite.get(tier, by_sprite.get("0", [])), rng)
