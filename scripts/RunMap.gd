## Carte de strate à embranchements (façon Slay the Spire) : un graphe en
## couches que le joueur remonte en choisissant sa voie. Dernière rangée = boss.
class_name RunMap
extends RefCounted

const ROWS := 8

# nodes[row] = Array de nœuds { type, row, idx, edges:Array[int vers row+1], x_frac }
var nodes: Array = []

# Strate courante (0-indexée) : plus elle est élevée, plus la carte devient dure
# (davantage d'Élite/Événement, au détriment du Combat simple, cf. _roll_type).
var act: int = 0

func _init(p_act: int, rng: RandomNumberGenerator) -> void:
	act = p_act
	_generate(rng)

func _generate(rng: RandomNumberGenerator) -> void:
	nodes.clear()
	for r in ROWS:
		var count: int
		if r == 0:
			count = 3
		elif r == ROWS - 1:
			count = 1
		else:
			count = rng.randi_range(2, 4)
		var row: Array = []
		for i in count:
			row.append({
				"type": _roll_type(r, rng),
				"row": r, "idx": i, "edges": [],
				"x_frac": (i + 1.0) / (count + 1.0),
			})
		nodes.append(row)

	for r in ROWS - 1:
		var cur: Array = nodes[r]
		var nxt: Array = nodes[r + 1]
		for node in cur:
			var order: Array = _by_proximity(node["x_frac"], nxt)
			var links: int = 1 if nxt.size() == 1 else rng.randi_range(1, 2)
			for k in min(links, order.size()):
				if not node["edges"].has(order[k]):
					node["edges"].append(order[k])
		# garantit qu'aucun nœud de la rangée suivante n'est orphelin
		for j in nxt.size():
			var reachable := false
			for node in cur:
				if node["edges"].has(j):
					reachable = true
					break
			if not reachable:
				cur[_nearest_idx(cur, nxt[j]["x_frac"])]["edges"].append(j)

func _roll_type(r: int, rng: RandomNumberGenerator) -> String:
	if r == 0:
		return "combat"
	if r == ROWS - 1:
		return "boss"
	if r == ROWS - 2:
		return "rest" if rng.randf() < 0.5 else "shop"
	# Plus la strate (act) est élevée, plus Élite et Événement grignotent la part
	# du Combat simple — plafonné pour ne jamais l'éliminer complètement.
	var elite_bonus: float = minf(0.10, act * 0.015)
	var event_bonus: float = minf(0.06, act * 0.01)
	var combat_top: float = maxf(0.30, 0.50 - elite_bonus - event_bonus)
	var elite_top: float = combat_top + 0.14 + elite_bonus
	var shop_top: float = elite_top + 0.15
	var event_top: float = shop_top + 0.15 + event_bonus
	var roll: float = rng.randf()
	if roll < combat_top:
		return "combat"
	elif roll < elite_top:
		return "elite"
	elif roll < shop_top:
		return "shop"
	elif roll < event_top:
		return "event"
	return "rest"

func _by_proximity(x_frac: float, row: Array) -> Array:
	var idxs: Array = range(row.size())
	idxs.sort_custom(func(a, b): return absf(row[a]["x_frac"] - x_frac) < absf(row[b]["x_frac"] - x_frac))
	return idxs

func _nearest_idx(row: Array, x_frac: float) -> int:
	var best := 0
	var bd := 999.0
	for i in row.size():
		var d: float = absf(row[i]["x_frac"] - x_frac)
		if d < bd:
			bd = d
			best = i
	return best
