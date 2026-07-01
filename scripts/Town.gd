## Le Hub — pied de la Tour : petite ville explorable, hors run, où Aria se
## déplace librement (pas de tour par tour/combat) pour accéder aux écrans de
## méta-progression via des bâtiments plutôt qu'une liste de boutons plate.
## Disposition fixe, dessinée à la main (pas de génération procédurale : c'est
## un lieu, pas un donjon).
class_name Town
extends RefCounted

const WALL := 0    # bordure infranchissable
const FLOOR := 1   # herbe praticable
const ROAD := 2    # chemin praticable (décoratif)

const WIDTH := 17
const HEIGHT := 13

var tiles: Array = []             # tiles[y][x]
var buildings: Dictionary = {}    # Vector2i -> { id, name, glyph, color }
var player_start := Vector2i(8, 6)

func _init() -> void:
	_build()

func _build() -> void:
	tiles.clear()
	for y in HEIGHT:
		var row: Array = []
		for x in WIDTH:
			var edge: bool = x == 0 or x == WIDTH - 1 or y == 0 or y == HEIGHT - 1
			row.append(WALL if edge else FLOOR)
		tiles.append(row)

	# Croix de chemins reliant la place centrale aux bâtiments.
	for x in range(2, WIDTH - 2):
		tiles[6][x] = ROAD
	for y in range(2, HEIGHT - 2):
		tiles[y][8] = ROAD

	buildings = {
		Vector2i(8, 2): { "id": "tower_gate", "name": "Porte de la Tour",
			"glyph": "⛫", "color": Color(0.72, 0.62, 1.0) },
		Vector2i(3, 5): { "id": "armurerie", "name": "Armurerie",
			"glyph": "🛡", "color": Color(0.85, 0.6, 0.35) },
		Vector2i(13, 5): { "id": "bibliotheque", "name": "Bibliothèque",
			"glyph": "📖", "color": Color(0.55, 0.75, 1.0) },
		Vector2i(3, 9): { "id": "sanctuaire", "name": "Sanctuaire",
			"glyph": "✦", "color": Color(0.85, 0.7, 0.35) },
		Vector2i(13, 9): { "id": "forge", "name": "Forge",
			"glyph": "⚒", "color": Color(0.95, 0.45, 0.3) },
		Vector2i(8, 10): { "id": "boutique", "name": "Boutique",
			"glyph": "🏪", "color": Color(0.5, 0.95, 0.75) },
	}
	# Dégage le sol sous chaque bâtiment (au cas où il tomberait sur un mur).
	for p in buildings.keys():
		if _in_bounds(p.x, p.y):
			tiles[p.y][p.x] = FLOOR

func _in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < WIDTH and y >= 0 and y < HEIGHT

func is_walkable(x: int, y: int) -> bool:
	if not _in_bounds(x, y):
		return false
	return tiles[y][x] != WALL

func building_at(x: int, y: int) -> Dictionary:
	return buildings.get(Vector2i(x, y), {})
