## Rendu du Hub (pied de la Tour) : petite ville fixe, sans brouillard de guerre
## ni caméra de suivi (la carte entière tient à l'écran). Réutilise les
## textures du biome "plaine" pour le sol/chemin ; les bâtiments n'ont pas
## encore de sprite dédié — panneau coloré + glyphe en attendant.
extends Node2D

const CELL := 32
const VIEW := Vector2(1280, 720)
const COLOR_GRASS := Color(0.10, 0.14, 0.10)
const COLOR_ROAD := Color(0.16, 0.14, 0.12)
const COLOR_WALL := Color(0.05, 0.045, 0.07)

var town: Town = null
var hub_pos: Vector2i = Vector2i.ZERO
var tex: Dictionary = {}
var _font: Font

func _ready() -> void:
	_font = ThemeDB.fallback_font
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_load_textures()

func _load_textures() -> void:
	for n in ["plaine_ground", "plaine_tree", "road", "aria"]:
		var path := "res://assets/%s.png" % n
		tex[n] = load(path) if ResourceLoader.exists(path) else null

func refresh(t: Town, pos: Vector2i) -> void:
	town = t
	hub_pos = pos
	queue_redraw()

func _draw() -> void:
	if town == null:
		return
	# Fond plein écran défensif : la ville (petite, fixe) ne couvre pas tout
	# l'écran, ce rectangle évite qu'un rendu de donjon résiduel ne transparaisse
	# dans les marges si jamais la visibilité de map_view n'était pas à jour.
	draw_rect(Rect2(0, 0, VIEW.x, VIEW.y), Color(0.045, 0.055, 0.05))
	var tw: float = Town.WIDTH * CELL
	var th: float = Town.HEIGHT * CELL
	var ox: float = round((VIEW.x - tw) * 0.5)
	var oy: float = round((VIEW.y - th) * 0.5)

	for y in Town.HEIGHT:
		for x in Town.WIDTH:
			var t: int = town.tiles[y][x]
			var px: float = ox + x * CELL
			var py: float = oy + y * CELL
			if t == Town.WALL:
				_blit_or_rect("plaine_tree", Rect2(px, py, CELL, CELL), COLOR_WALL)
			elif t == Town.ROAD:
				_blit_or_rect("road", Rect2(px, py, CELL, CELL), COLOR_ROAD)
			else:
				_blit_or_rect("plaine_ground", Rect2(px, py, CELL, CELL), COLOR_GRASS)

	# Bâtiments : panneau coloré + glyphe + nom, débordant un peu de la case
	# pour lire comme un petit édifice plutôt qu'un simple marqueur au sol.
	for p in town.buildings.keys():
		var b: Dictionary = town.buildings[p]
		var col: Color = b["color"]
		var px: float = ox + p.x * CELL
		var py: float = oy + p.y * CELL
		var rect := Rect2(px - 8, py - 26, CELL + 16, CELL + 26)
		draw_rect(rect, Color(col.r * 0.16, col.g * 0.14, col.b * 0.20, 0.95))
		draw_rect(rect, col, false, 2.0)
		draw_string(_font, Vector2(px - 8, py - 4), b["glyph"],
			HORIZONTAL_ALIGNMENT_CENTER, CELL + 16, 20, col)
		draw_string(_font, Vector2(px - 54, py + CELL + 16), b["name"],
			HORIZONTAL_ALIGNMENT_CENTER, CELL + 108, 12, Color(0.88, 0.88, 0.94))

	# Aria, au pied de la Tour.
	var apx: float = ox + hub_pos.x * CELL
	var apy: float = oy + hub_pos.y * CELL
	_blit_or_rect("aria", Rect2(apx, apy, CELL, CELL), Color(0.92, 0.55, 0.85))

## Dessine la texture nommée si chargée, sinon un rectangle de repli — même
## logique de repli que MapView (pas de crash si un asset manque).
func _blit_or_rect(name: String, rect: Rect2, fallback: Color) -> void:
	var t: Texture2D = tex.get(name)
	if t != null:
		draw_texture_rect(t, rect, false)
	else:
		draw_rect(rect, fallback)
