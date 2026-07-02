## Génération procédurale d'un étage "open world" biome-thématique.
## Le terrain est un grand plan ouvert (bien plus large que l'écran) parsemé
## d'éléments (arbres, rochers, eau, routes, décor) selon le biome courant.
## Gère aussi le BROUILLARD DE GUERRE (explored / visible) révélé par la vision.
class_name Dungeon
extends RefCounted

# Types de tuiles. Walkable = GROUND, ROAD. Bloquantes = WALL, WATER, TREE, ROCK.
const WALL := 0     # bordure / vide infranchissable
const FLOOR := 1    # sol praticable (GROUND) — conservé pour compat
const ROAD := 2     # chemin praticable (décoratif)
const WATER := 3
const TREE := 4
const ROCK := 5

# Effets de terrain (Phase 4 — couche élémentaire). EFF_BURNT réécrit tiles[]
# en FLOOR ; les autres sont purement additifs par-dessus le tile de base.
const EFF_NONE := 0
const EFF_BURNING := 1
const EFF_BURNT := 2
const EFF_FROZEN := 3
const EFF_CLOUD := 4

var width: int
var height: int
var tiles: Array = []           # tiles[y][x] -> type de tuile
var decor: Array = []           # decor[y][x] -> nom de sprite décoratif ("" si aucun)
var obstacle: Array = []        # obstacle[y][x] -> variante de sprite pour une case ROCK ("" = rocher du biome)
var explored: Array = []        # explored[y][x] -> déjà vue (mémoire, dessinée en sombre)
var visible: Array = []         # visible[y][x] -> dans le champ de vision actuel
var biome: Dictionary = {}      # biome courant (Data.BIOMES[i])
var start: Vector2i = Vector2i.ZERO
var stairs: Vector2i = Vector2i.ZERO
var reachable_tiles: Array = []  # cases praticables atteignables (calculé une fois)

var effects: Array = []             # effects[y][x] -> EFF_* (grille pleine, lecture O(1))
var effect_timer: Array = []        # effect_timer[y][x] -> tours restants pour l'effet courant
var active_effects: Array = []      # Array[Vector2i] : cases avec un effet actif — TOUJOURS itérer cette liste, jamais la grille pleine (640x400)

var _rng: RandomNumberGenerator
var _vis_cells: Array = []       # cases actuellement visibles (pour effacer vite)

func _init(w: int, h: int, rng: RandomNumberGenerator, biome_def: Dictionary = {}) -> void:
	width = w
	height = h
	_rng = rng
	biome = biome_def if not biome_def.is_empty() else Data.BIOMES[0]
	_generate(rng)

# --- Génération ---------------------------------------------------------------
func _generate(rng: RandomNumberGenerator) -> void:
	_fill(FLOOR)
	decor = _make_grid("")
	obstacle = _make_grid("")
	explored = _make_grid(false)
	visible = _make_grid(false)
	effects = _make_grid(EFF_NONE)
	effect_timer = _make_grid(0)
	active_effects = []

	# Bordure infranchissable (cadre de la carte)
	for x in width:
		tiles[0][x] = ROCK
		tiles[height - 1][x] = ROCK
	for y in height:
		tiles[y][0] = ROCK
		tiles[y][width - 1] = ROCK

	var area: int = width * height
	# Étendues d'eau (mares / rivières) en amas
	_scatter_clusters(WATER, int(area * float(biome.get("water_density", 0.04)) / 6.0), 4, 14, rng)
	# Un grand lac, occasionnel — plus probable/visible dans les biomes humides.
	var water_density: float = float(biome.get("water_density", 0.04))
	if rng.randf() < clampf(water_density * 4.0, 0.2, 0.9):
		_scatter_clusters(WATER, 1, 30, 70, rng)
	# Bosquets d'arbres
	_scatter_clusters(TREE, int(area * float(biome.get("tree_density", 0.06)) / 4.0), 2, 9, rng)
	# Rochers (petits amas + isolés)
	_scatter_clusters(ROCK, int(area * float(biome.get("rock_density", 0.04)) / 3.0), 1, 5, rng)
	# Variantes d'obstacles (tronc abattu / colonne en ruine), avec modération.
	_scatter_obstacle_variants(rng)

	# Point d'entrée et escalier (coins opposés, sur du sol)
	start = _clear_spot(Vector2i(rng.randi_range(2, 5), rng.randi_range(2, 5)))
	stairs = _clear_spot(Vector2i(width - rng.randi_range(3, 6), height - rng.randi_range(3, 6)))

	# Route praticable reliant l'entrée à l'escalier (déblaie le passage)
	_carve_path(start, stairs, biome.get("road", false))

	# Garantit la connexité : si l'escalier reste inatteignable, on force un couloir
	var reach: Dictionary = _reachable_set(start)
	if not reach.has(stairs):
		_carve_path(start, stairs, false, true)
		reach = _reachable_set(start)
	reachable_tiles = reach.keys()   # mis en cache : peuplement O(count), pas O(aire)

	_scatter_decor(rng)

func _fill(kind: int) -> void:
	tiles.clear()
	for y in height:
		var row: Array = []
		for x in width:
			row.append(kind)
		tiles.append(row)

func _make_grid(value):
	var g: Array = []
	for y in height:
		var row: Array = []
		for x in width:
			row.append(value)
		g.append(row)
	return g

## Dépose `seeds` amas du type donné, chacun d'une taille aléatoire (random walk).
func _scatter_clusters(kind: int, seeds: int, smin: int, smax: int, rng: RandomNumberGenerator) -> void:
	for s in max(0, seeds):
		var cx: int = rng.randi_range(1, width - 2)
		var cy: int = rng.randi_range(1, height - 2)
		var size: int = rng.randi_range(smin, smax)
		var x: int = cx
		var y: int = cy
		for i in size:
			if x > 0 and x < width - 1 and y > 0 and y < height - 1 and tiles[y][x] == FLOOR:
				tiles[y][x] = kind
			match rng.randi_range(0, 3):
				0: x += 1
				1: x -= 1
				2: y += 1
				3: y -= 1
			x = clampi(x, 1, width - 2)
			y = clampi(y, 1, height - 2)

## Dégage une case (et ses voisines) pour y placer un point d'intérêt.
func _clear_spot(p: Vector2i) -> Vector2i:
	p.x = clampi(p.x, 1, width - 2)
	p.y = clampi(p.y, 1, height - 2)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x: int = clampi(p.x + dx, 1, width - 2)
			var y: int = clampi(p.y + dy, 1, height - 2)
			tiles[y][x] = FLOOR
	return p

## Trace un chemin en L de a vers b ; en ROAD si `as_road`, sinon dégage juste le sol.
func _carve_path(a: Vector2i, b: Vector2i, as_road: bool, force: bool = false) -> void:
	var paint: int = ROAD if as_road else FLOOR
	var x: int = a.x
	var y: int = a.y
	while x != b.x:
		x += signi(b.x - x)
		_lay(x, y, paint, force)
	while y != b.y:
		y += signi(b.y - y)
		_lay(x, y, paint, force)

func _lay(x: int, y: int, paint: int, force: bool) -> void:
	if x <= 0 or x >= width - 1 or y <= 0 or y >= height - 1:
		return
	# Une route ne remplace pas l'eau (pas de pont) sauf si on force le passage.
	if tiles[y][x] == WATER and not force:
		tiles[y][x] = FLOOR
	else:
		tiles[y][x] = paint

func _scatter_decor(rng: RandomNumberGenerator) -> void:
	var styles: Array = biome.get("decor_styles", [Data.biome_sprite(biome["id"], "decor")])
	var density: float = float(biome.get("decor_density", 0.08))
	for y in height:
		for x in width:
			if tiles[y][x] != FLOOR:
				continue
			# Props du monde (feu de camp, caisses...) : rares, indépendants du biome,
			# prioritaires sur le décor du biome pour ne pas empiler les deux.
			if rng.randf() < Data.WORLD_PROPS_DENSITY:
				decor[y][x] = Data.weighted_pick(Data.WORLD_PROPS, rng)
			elif rng.randf() < density:
				var variant: int = rng.randi_range(0, styles.size() - 1)
				decor[y][x] = Data.biome_decor_sprite(biome["id"], variant)

## Variante de sprite pour certaines cases ROCK (tronc abattu, colonne en ruine)
## à la place du rocher du biome — apporte de la variété au terrain bloquant,
## utilisé avec modération (faible probabilité par case).
func _scatter_obstacle_variants(rng: RandomNumberGenerator) -> void:
	# Exclut le cadre extérieur (bordure infranchissable) : il doit rester un
	# mur de rocher uniforme plutôt qu'un mélange de troncs/colonnes en bord de carte.
	for y in range(1, height - 1):
		for x in range(1, width - 1):
			if tiles[y][x] == ROCK and rng.randf() < Data.OBSTACLE_VARIANT_CHANCE:
				obstacle[y][x] = Data.weighted_pick(Data.OBSTACLE_VARIANTS, rng)

# --- Connexité (BFS) ----------------------------------------------------------
func _reachable(a: Vector2i, b: Vector2i) -> bool:
	var seen: Dictionary = {}
	var queue: Array = [a]
	seen[a] = true
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		if cur == b:
			return true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if not seen.has(n) and is_walkable(n.x, n.y):
				seen[n] = true
				queue.append(n)
	return false

# --- API publique -------------------------------------------------------------
func _in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < width and y >= 0 and y < height

func is_walkable(x: int, y: int) -> bool:
	if not _in_bounds(x, y):
		return false
	var t: int = tiles[y][x]
	if t == FLOOR or t == ROAD:
		return true
	if t == WATER and effects[y][x] == EFF_FROZEN:
		return true          # glace : praticable tant qu'elle n'a pas fondu
	return false

## Recalcule le cache de connexité (reachable_tiles) après une mutation de
## terrain (arbre calciné, eau gelée/dégelée...). Le cache existant devient
## silencieusement obsolète sinon — à appeler une seule fois par lot de
## mutations (jamais par case individuelle).
func rebuild_reachability() -> void:
	var reach: Dictionary = _reachable_set(start)
	reachable_tiles = reach.keys()

## Ligne de vue de `a` vers `b` (Bresenham entier, cf. _assets_gen.gd::_line).
## Teste chaque case intermédiaire (a et b exclus) ; bloquée par WALL/TREE/ROCK
## (l'EAU ne bloque pas la vue). Pas symétrique entre octants — convention :
## toujours appeler has_los(attaquant, cible).
func has_los(a: Vector2i, b: Vector2i) -> bool:
	var dx: int = absi(b.x - a.x)
	var dy: int = -absi(b.y - a.y)
	var sx: int = 1 if a.x < b.x else -1
	var sy: int = 1 if a.y < b.y else -1
	var err: int = dx + dy
	var x: int = a.x
	var y: int = a.y
	while true:
		if x == b.x and y == b.y:
			return true
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy
		if x == b.x and y == b.y:
			return true
		if not _in_bounds(x, y):
			return false
		var t: int = tiles[y][x]
		if t == WALL or t == TREE or t == ROCK:
			return false

## Met à jour le brouillard de guerre : tout dans le rayon devient visible+exploré.
## N'efface que les cases précédemment visibles (rapide même sur immense carte).
func reveal(center: Vector2i, radius: int) -> void:
	for c in _vis_cells:
		visible[c.y][c.x] = false
	_vis_cells.clear()
	var r2: int = radius * radius
	for y in range(max(0, center.y - radius), min(height, center.y + radius + 1)):
		for x in range(max(0, center.x - radius), min(width, center.x + radius + 1)):
			var dx: int = x - center.x
			var dy: int = y - center.y
			if dx * dx + dy * dy <= r2:
				visible[y][x] = true
				explored[y][x] = true
				_vis_cells.append(Vector2i(x, y))

## Marque une case comme explorée (mémoire) sans toucher au champ de vision actuel.
## Utilisé par l'Œil du Devin pour révéler le butin à travers le brouillard.
func mark_explored(pos: Vector2i) -> void:
	if _in_bounds(pos.x, pos.y):
		explored[pos.y][pos.x] = true

func is_visible(x: int, y: int) -> bool:
	return _in_bounds(x, y) and visible[y][x]

func is_explored(x: int, y: int) -> bool:
	return _in_bounds(x, y) and explored[y][x]

## Positions praticables aléatoires ATTEIGNABLES depuis `start`, hors `exclude`.
## Échantillonnage par indices aléatoires (O(count)) sur le cache reachable_tiles.
func random_floor_tiles(count: int, rng: RandomNumberGenerator, exclude: Array) -> Array:
	var result: Array = []
	if reachable_tiles.is_empty():
		return result
	var used: Dictionary = {}
	for p in exclude:
		used[p] = true
	var tries: int = 0
	var budget: int = count * 40 + 50
	while result.size() < count and tries < budget:
		tries += 1
		var p: Vector2i = reachable_tiles[rng.randi_range(0, reachable_tiles.size() - 1)]
		if used.has(p):
			continue
		used[p] = true
		result.append(p)
	return result

## Comme random_floor_tiles, mais restreint aux cases à distance de Tchebychev
## <= radius de `center` (pour éviter des gardiens de boss à l'autre bout de la carte).
## Complète depuis l'échantillon global si le voisinage n'a pas assez de cases.
func random_floor_tiles_near(center: Vector2i, radius: int, count: int,
		rng: RandomNumberGenerator, exclude: Array) -> Array:
	var near: Array = []
	for p in reachable_tiles:
		if maxi(absi(p.x - center.x), absi(p.y - center.y)) <= radius:
			near.append(p)
	var used: Dictionary = {}
	for p in exclude:
		used[p] = true
	var result: Array = []
	var tries: int = 0
	var budget: int = count * 40 + 50
	while result.size() < count and tries < budget and not near.is_empty():
		tries += 1
		var p: Vector2i = near[rng.randi_range(0, near.size() - 1)]
		if used.has(p):
			continue
		used[p] = true
		result.append(p)
	if result.size() < count:
		for p in random_floor_tiles(count - result.size(), rng, exclude + result):
			result.append(p)
	return result

## A* 4-connexe (heuristique de Manhattan) : renvoie la PROCHAINE case vers
## laquelle avancer depuis `from` pour rejoindre `to` (pas le chemin entier).
## Seul le terrain compte — les autres entités sont traitées comme praticables,
## la collision se résout déjà au moment du déplacement. S'arrête après
## `max_nodes` expansions (petites arènes, appelé au plus 1x/tour/entité) et
## renvoie `from` (aucun mouvement) si aucun chemin n'est trouvé à temps.
func next_step(from: Vector2i, to: Vector2i, max_nodes: int = 400) -> Vector2i:
	if from == to or not is_walkable(to.x, to.y):
		return from
	var open: Array = [from]
	var g_score: Dictionary = { from: 0 }
	var came_from: Dictionary = {}
	var closed: Dictionary = {}
	var expansions: int = 0
	while not open.is_empty() and expansions < max_nodes:
		var best_i: int = 0
		var best_f: int = g_score[open[0]] + _manhattan_h(open[0], to)
		for i in range(1, open.size()):
			var f: int = g_score[open[i]] + _manhattan_h(open[i], to)
			if f < best_f:
				best_f = f
				best_i = i
		var current: Vector2i = open[best_i]
		open.remove_at(best_i)
		if current == to:
			var step: Vector2i = current
			while came_from.has(step) and came_from[step] != from:
				step = came_from[step]
			return step
		closed[current] = true
		expansions += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = current + d
			if closed.has(n) or not is_walkable(n.x, n.y):
				continue
			var tentative_g: int = g_score[current] + 1
			if not g_score.has(n) or tentative_g < g_score[n]:
				g_score[n] = tentative_g
				came_from[n] = current
				if not open.has(n):
					open.append(n)
	return from

func _manhattan_h(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _reachable_set(a: Vector2i) -> Dictionary:
	var seen: Dictionary = {}
	if not is_walkable(a.x, a.y):
		return seen
	var queue: Array = [a]
	seen[a] = true
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if not seen.has(n) and is_walkable(n.x, n.y):
				seen[n] = true
				queue.append(n)
	return seen
