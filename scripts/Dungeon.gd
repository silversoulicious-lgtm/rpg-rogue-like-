## Génération procédurale d'un étage de la tour : salles + couloirs.
## Chaque étage est un nouveau plan (roguelike : layout différent à chaque fois).
class_name Dungeon
extends RefCounted

const WALL := 0
const FLOOR := 1

var width: int
var height: int
var tiles: Array = []          # tiles[y][x] -> WALL / FLOOR
var rooms: Array = []          # Array[Rect2i]
var start: Vector2i = Vector2i.ZERO   # où le héros apparaît
var stairs: Vector2i = Vector2i.ZERO  # l'escalier '>' vers l'étage suivant

func _init(w: int, h: int, rng: RandomNumberGenerator) -> void:
	width = w
	height = h
	_generate(rng)

func _generate(rng: RandomNumberGenerator) -> void:
	tiles.clear()
	for y in height:
		var row: Array = []
		for x in width:
			row.append(WALL)
		tiles.append(row)

	rooms.clear()
	var max_rooms := 11
	var attempts := 60
	for i in attempts:
		if rooms.size() >= max_rooms:
			break
		var rw := rng.randi_range(4, 8)
		var rh := rng.randi_range(4, 6)
		var rx := rng.randi_range(1, max(1, width - rw - 1))
		var ry := rng.randi_range(1, max(1, height - rh - 1))
		var rect := Rect2i(rx, ry, rw, rh)
		var overlaps := false
		for other in rooms:
			if rect.grow(1).intersects(other):
				overlaps = true
				break
		if overlaps:
			continue
		_carve_room(rect)
		if not rooms.is_empty():
			var prev: Vector2i = rooms[rooms.size() - 1].get_center()
			_carve_corridor(prev, rect.get_center(), rng)
		rooms.append(rect)

	# Sécurité : au moins une salle (sinon carte vide)
	if rooms.is_empty():
		var fallback := Rect2i(1, 1, width - 2, height - 2)
		_carve_room(fallback)
		rooms.append(fallback)

	start = rooms[0].get_center()
	stairs = rooms[rooms.size() - 1].get_center()

func _carve_room(rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if _in_bounds(x, y):
				tiles[y][x] = FLOOR

func _carve_corridor(a: Vector2i, b: Vector2i, rng: RandomNumberGenerator) -> void:
	# Couloir en L, ordre horizontal/vertical aléatoire.
	if rng.randf() < 0.5:
		_carve_h(a.x, b.x, a.y)
		_carve_v(a.y, b.y, b.x)
	else:
		_carve_v(a.y, b.y, a.x)
		_carve_h(a.x, b.x, b.y)

func _carve_h(x1: int, x2: int, y: int) -> void:
	for x in range(min(x1, x2), max(x1, x2) + 1):
		if _in_bounds(x, y):
			tiles[y][x] = FLOOR

func _carve_v(y1: int, y2: int, x: int) -> void:
	for y in range(min(y1, y2), max(y1, y2) + 1):
		if _in_bounds(x, y):
			tiles[y][x] = FLOOR

func _in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < width and y >= 0 and y < height

func is_walkable(x: int, y: int) -> bool:
	return _in_bounds(x, y) and tiles[y][x] == FLOOR

## Renvoie des positions de sol aléatoires, en évitant `exclude` (positions occupées).
func random_floor_tiles(count: int, rng: RandomNumberGenerator, exclude: Array) -> Array:
	var candidates: Array = []
	for y in height:
		for x in width:
			if tiles[y][x] == FLOOR:
				var p := Vector2i(x, y)
				if not exclude.has(p):
					candidates.append(p)
	candidates.shuffle()
	# shuffle() utilise le RNG global ; on mélange aussi avec notre rng pour le déterminisme
	var result: Array = []
	for i in min(count, candidates.size()):
		result.append(candidates[i])
	return result
