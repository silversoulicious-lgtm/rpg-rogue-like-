## Rendu ASCII-roguelike de la grille via _draw().
## 100% code, aucun asset : remplaçable plus tard par des tuiles/sprites.
extends Node2D

const CELL := 26
const COLOR_WALL := Color(0.22, 0.20, 0.32)
const COLOR_FLOOR := Color(0.10, 0.09, 0.15)
const COLOR_FLOOR_GLYPH := Color(0.30, 0.28, 0.40)
const COLOR_STAIRS := Color(1.0, 0.85, 0.3)

var dungeon: Dungeon = null
var entities: Array = []          # Array[Entity]
var _font: Font
var _font_size := 22

func _ready() -> void:
	_font = ThemeDB.fallback_font

func refresh(d: Dungeon, ents: Array) -> void:
	dungeon = d
	entities = ents
	queue_redraw()

func grid_pixel_size() -> Vector2:
	if dungeon == null:
		return Vector2.ZERO
	return Vector2(dungeon.width * CELL, dungeon.height * CELL)

func _draw() -> void:
	if dungeon == null:
		return
	# Fond + tuiles
	for y in dungeon.height:
		for x in dungeon.width:
			var rpos := Vector2(x * CELL, y * CELL)
			if dungeon.tiles[y][x] == Dungeon.FLOOR:
				draw_rect(Rect2(rpos, Vector2(CELL, CELL)), COLOR_FLOOR, true)
				_draw_glyph(x, y, ".", COLOR_FLOOR_GLYPH)
			else:
				draw_rect(Rect2(rpos, Vector2(CELL, CELL)), COLOR_WALL, true)
	# Escalier
	_draw_glyph(dungeon.stairs.x, dungeon.stairs.y, ">", COLOR_STAIRS)
	# Entités (par-dessus)
	for e in entities:
		if e.is_alive():
			_draw_glyph(e.x, e.y, e.glyph, e.color)
			_draw_hp_pip(e)

func _draw_glyph(gx: int, gy: int, ch: String, col: Color) -> void:
	if _font == null:
		return
	var size := _font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size)
	var origin := Vector2(
		gx * CELL + (CELL - size.x) * 0.5,
		gy * CELL + (CELL + size.y) * 0.5 - size.y * 0.25
	)
	draw_char(_font, origin, ch, _font_size, col)

func _draw_hp_pip(e: Entity) -> void:
	# Petite barre de vie sous l'entité (ennemis blessés / héros).
	if e.hp >= e.max_hp and e.faction == Entity.Faction.ENEMY:
		return
	var ratio: float = clampf(float(e.hp) / float(e.max_hp), 0.0, 1.0)
	var bar_w := float(CELL - 8)
	var bx := e.x * CELL + 4.0
	var by := e.y * CELL + CELL - 4.0
	draw_rect(Rect2(Vector2(bx, by), Vector2(bar_w, 3)), Color(0.2, 0.05, 0.05), true)
	var col := Color(0.3, 0.85, 0.3) if e.faction == Entity.Faction.PLAYER else Color(0.85, 0.3, 0.3)
	draw_rect(Rect2(Vector2(bx, by), Vector2(bar_w * ratio, 3)), col, true)
