## Rendu du donjon par tuiles : textures de monde + sprites.
## Repli automatique sur des glyphes ASCII si une texture est absente.
extends Node2D

const CELL := 24          # = taille native des tuiles (assets 24x24) -> rendu net 1:1
const COLOR_WALL := Color(0.22, 0.20, 0.32)
const COLOR_FLOOR := Color(0.10, 0.09, 0.15)
const COLOR_FLOOR_GLYPH := Color(0.30, 0.28, 0.40)
const COLOR_STAIRS := Color(1.0, 0.85, 0.3)

var dungeon: Dungeon = null
var entities: Array = []          # Array[Entity]
var loot: Array = []              # Array[dict] : { pos, sprite, glyph, color }
var tex: Dictionary = {}          # nom -> Texture2D
var _font: Font
var _font_size := 20

func _ready() -> void:
	_font = ThemeDB.fallback_font
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # pixel-art net
	_load_textures()

func _load_textures() -> void:
	var names := ["floor", "wall", "stairs", "knight", "mage", "ranger",
		"gobelin", "loup", "squelette", "orc", "spectre", "boss",
		"arme", "armure", "relique", "artifact", "potion"]
	for n in names:
		var path := "res://assets/%s.png" % n
		if ResourceLoader.exists(path):
			tex[n] = load(path)

func refresh(d: Dungeon, ents: Array, loot_items: Array) -> void:
	dungeon = d
	entities = ents
	loot = loot_items
	queue_redraw()

func grid_pixel_size() -> Vector2:
	if dungeon == null:
		return Vector2.ZERO
	return Vector2(dungeon.width * CELL, dungeon.height * CELL)

func _draw() -> void:
	if dungeon == null:
		return
	# Sol & murs
	for y in dungeon.height:
		for x in dungeon.width:
			if dungeon.tiles[y][x] == Dungeon.FLOOR:
				if not _blit("floor", x, y):
					draw_rect(_cell_rect(x, y), COLOR_FLOOR, true)
					_draw_glyph(x, y, ".", COLOR_FLOOR_GLYPH)
			else:
				if not _blit("wall", x, y):
					draw_rect(_cell_rect(x, y), COLOR_WALL, true)
	# Escalier
	if not _blit("stairs", dungeon.stairs.x, dungeon.stairs.y):
		_draw_glyph(dungeon.stairs.x, dungeon.stairs.y, ">", COLOR_STAIRS)
	# Butin
	for item in loot:
		var p: Vector2i = item["pos"]
		if not _blit(item.get("sprite", ""), p.x, p.y):
			_draw_glyph(p.x, p.y, item["glyph"], item["color"])
	# Entités
	for e in entities:
		if e.is_alive():
			if not _blit(e.sprite, e.x, e.y):
				_draw_glyph(e.x, e.y, e.glyph, e.color)
			_draw_hp_pip(e)

func _cell_rect(gx: int, gy: int) -> Rect2:
	return Rect2(Vector2(gx * CELL, gy * CELL), Vector2(CELL, CELL))

func _blit(name: String, gx: int, gy: int) -> bool:
	if name == "" or not tex.has(name):
		return false
	draw_texture_rect(tex[name], _cell_rect(gx, gy), false)
	return true

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
	if e.hp >= e.max_hp and e.faction == Entity.Faction.ENEMY:
		return
	var ratio: float = clampf(float(e.hp) / float(e.max_hp), 0.0, 1.0)
	var bar_w := float(CELL - 6)
	var bx := e.x * CELL + 3.0
	var by := e.y * CELL + CELL - 3.0
	draw_rect(Rect2(Vector2(bx, by), Vector2(bar_w, 3)), Color(0.15, 0.03, 0.03), true)
	var col := Color(0.3, 0.85, 0.3) if e.faction == Entity.Faction.PLAYER else Color(0.85, 0.3, 0.3)
	draw_rect(Rect2(Vector2(bx, by), Vector2(bar_w * ratio, 3)), col, true)
