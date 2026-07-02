## Rendu du Hub (pied de la Tour) : petite ville fixe, sans brouillard de guerre
## ni caméra de suivi (la carte entière tient à l'écran). Réutilise les
## textures du biome "plaine" pour le sol/chemin ; les bâtiments ont leur
## propre sprite dédié (generés par _assets_gen.gd, cf. building_<id>.png),
## plus grand qu'une tuile pour lire comme un vrai lieu plutôt qu'une icône.
extends Node2D

const CELL := 32
const BW := 64   # doit rester en phase avec BW/BH de _assets_gen.gd
const BH := 88
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
	for n in ["plaine_ground", "plaine_tree", "road", "aria",
			"building_armurerie", "building_bibliotheque", "building_sanctuaire",
			"building_forge", "building_boutique", "building_tower_gate"]:
		var path := "res://assets/%s.png" % n
		tex[n] = load(path) if ResourceLoader.exists(path) else null

func refresh(t: Town, pos: Vector2i) -> void:
	town = t
	hub_pos = pos
	queue_redraw()

func _draw() -> void:
	if town == null:
		return
	var view: Vector2 = get_viewport_rect().size
	# Fond plein écran défensif : la ville (petite, fixe) ne couvre pas tout
	# l'écran, ce rectangle évite qu'un rendu de donjon résiduel ne transparaisse
	# dans les marges si jamais la visibilité de map_view n'était pas à jour.
	draw_rect(Rect2(0, 0, view.x, view.y), Color(0.045, 0.055, 0.05))
	var tw: float = Town.WIDTH * CELL
	var th: float = Town.HEIGHT * CELL
	var ox: float = round((view.x - tw) * 0.5)
	var oy: float = round((view.y - th) * 0.5)

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

	# Bâtiments : sprite dédié (2x2 tuiles), ancré par sa base sur la case du
	# bâtiment — il déborde vers le haut/les côtés pour lire comme un édifice
	# plutôt qu'un simple marqueur au sol. Nom affiché en dessous.
	for p in town.buildings.keys():
		var b: Dictionary = town.buildings[p]
		var px: float = ox + p.x * CELL
		var py: float = oy + p.y * CELL
		var bx: float = px + CELL * 0.5 - BW * 0.5
		var by: float = py + CELL - BH + 6.0
		_blit_or_rect("building_%s" % b["id"], Rect2(bx, by, BW, BH), b["color"])
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
