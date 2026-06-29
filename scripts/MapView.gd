## Rendu du terrain "open world" par tuiles, biome-thématique, avec brouillard
## de guerre et caméra (culling au viewport). Repli ASCII si une texture manque.
extends Node2D

const CELL := 24          # taille native des tuiles (assets 24x24)
const COLOR_FLOOR := Color(0.12, 0.13, 0.10)
const COLOR_GLYPH := Color(0.30, 0.34, 0.28)
const COLOR_STAIRS := Color(1.0, 0.85, 0.3)
const COLOR_FOG := Color(0.02, 0.02, 0.03)        # non exploré
const COLOR_MEMORY := Color(0.02, 0.02, 0.03, 0.55) # exploré mais hors vision

var dungeon: Dungeon = null
var entities: Array = []
var loot: Array = []
var reveal_loot: bool = false      # Œil du Devin : montre le butin à travers le brouillard
var tex: Dictionary = {}
var view_size: Vector2 = Vector2(896, 570)        # zone de jeu visible (réglée par Main)
var _font: Font
var _font_size := 18

func _ready() -> void:
	_font = ThemeDB.fallback_font
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_load_textures()

func _load_textures() -> void:
	var names := ["stairs", "aria", "aria_back", "aria_side", "knight", "mage", "ranger",
		"gobelin", "loup", "squelette", "orc", "spectre", "boss",
		"arme", "armure", "relique", "artifact", "potion", "road"]
	for b in Data.BIOMES:
		for role in ["ground", "tree", "rock", "water", "decor"]:
			names.append(Data.biome_sprite(b["id"], role))
	for n in names:
		var path := "res://assets/%s.png" % n
		if ResourceLoader.exists(path):
			tex[n] = load(path)

func refresh(d: Dungeon, ents: Array, loot_items: Array) -> void:
	dungeon = d
	entities = ents
	loot = loot_items
	queue_redraw()

# --- Dessin -------------------------------------------------------------------
func _draw() -> void:
	if dungeon == null:
		return
	var bid: String = str(dungeon.biome.get("id", "plaine"))
	# Fenêtre visible (culling) : on ne dessine que les tuiles à l'écran.
	var origin: Vector2 = -position
	var min_tx: int = max(0, int(floor(origin.x / CELL)))
	var min_ty: int = max(0, int(floor(origin.y / CELL)))
	var max_tx: int = min(dungeon.width - 1, int(floor((origin.x + view_size.x) / CELL)))
	var max_ty: int = min(dungeon.height - 1, int(floor((origin.y + view_size.y) / CELL)))

	for ty in range(min_ty, max_ty + 1):
		for tx in range(min_tx, max_tx + 1):
			if not dungeon.explored[ty][tx]:
				draw_rect(_cell_rect(tx, ty), COLOR_FOG, true)
				continue
			_draw_terrain(bid, tx, ty)
			if not dungeon.visible[ty][tx]:
				draw_rect(_cell_rect(tx, ty), COLOR_MEMORY, true)   # mémoire (assombrie)

	# Escalier : visible dès qu'il a été exploré (repère).
	var st: Vector2i = dungeon.stairs
	if dungeon.explored[st.y][st.x]:
		if not _blit("stairs", st.x, st.y):
			_draw_glyph(st.x, st.y, ">", COLOR_STAIRS)
		if not dungeon.visible[st.y][st.x]:
			draw_rect(_cell_rect(st.x, st.y), COLOR_MEMORY, true)

	# Butin & entités : uniquement dans le champ de vision actuel.
	for item in loot:
		var p: Vector2i = item["pos"]
		var seen: bool = dungeon.is_visible(p.x, p.y)
		# Œil du Devin : le butin déjà exploré reste affiché (assombri) à travers le brouillard.
		if seen or (reveal_loot and dungeon.is_explored(p.x, p.y)):
			if not _blit(item.get("sprite", ""), p.x, p.y):
				_draw_glyph(p.x, p.y, item["glyph"], item["color"])
			if not seen:
				draw_rect(_cell_rect(p.x, p.y), COLOR_MEMORY, true)
	for e in entities:
		if e.is_alive() and dungeon.is_visible(e.x, e.y):
			var dv: Dictionary = _directional_sprite(e)
			if not _blit_ex(dv["name"], e.x, e.y, dv["flip"]):
				_draw_glyph(e.x, e.y, e.glyph, e.color)
			_draw_hp_pip(e)

func _draw_terrain(bid: String, x: int, y: int) -> void:
	var t: int = dungeon.tiles[y][x]
	match t:
		Dungeon.WATER:
			if not _blit(Data.biome_sprite(bid, "water"), x, y):
				draw_rect(_cell_rect(x, y), dungeon.biome.get("water", Color(0.2, 0.4, 0.8)), true)
		Dungeon.ROAD:
			if not _blit("road", x, y):
				if not _blit(Data.biome_sprite(bid, "ground"), x, y):
					draw_rect(_cell_rect(x, y), COLOR_FLOOR, true)
		Dungeon.TREE:
			_draw_ground(bid, x, y)
			if not _blit(Data.biome_sprite(bid, "tree"), x, y):
				_draw_glyph(x, y, "♣", dungeon.biome.get("leaf", Color(0.3, 0.6, 0.3)))
		Dungeon.ROCK:
			_draw_ground(bid, x, y)
			if not _blit(Data.biome_sprite(bid, "rock"), x, y):
				draw_rect(_cell_rect(x, y).grow(-4), dungeon.biome.get("rock", Color(0.5, 0.5, 0.55)), true)
		_:
			_draw_ground(bid, x, y)
			var dn: String = dungeon.decor[y][x]
			if dn != "":
				_blit(dn, x, y)

func _draw_ground(bid: String, x: int, y: int) -> void:
	if not _blit(Data.biome_sprite(bid, "ground"), x, y):
		draw_rect(_cell_rect(x, y), COLOR_FLOOR, true)
		_draw_glyph(x, y, ".", COLOR_GLYPH)

func _cell_rect(gx: int, gy: int) -> Rect2:
	return Rect2(Vector2(gx * CELL, gy * CELL), Vector2(CELL, CELL))

func _blit(name: String, gx: int, gy: int) -> bool:
	if name == "" or not tex.has(name):
		return false
	draw_texture_rect(tex[name], _cell_rect(gx, gy), false)
	return true

## Variante de _blit avec miroir horizontal optionnel (sprites directionnels).
func _blit_ex(name: String, gx: int, gy: int, flip: bool) -> bool:
	if name == "" or not tex.has(name):
		return false
	var r: Rect2 = _cell_rect(gx, gy)
	if flip:
		r = Rect2(r.position.x + r.size.x, r.position.y, -r.size.x, r.size.y)   # largeur négative = miroir
	draw_texture_rect(tex[name], r, false)
	return true

## Choisit la vue d'une entité selon son orientation. Seule Aria possède des
## vues directionnelles (face/dos/profil) ; les autres gardent leur sprite unique.
func _directional_sprite(e) -> Dictionary:
	var name: String = e.sprite
	var flip := false
	if name == "aria":
		var f: Vector2i = e.facing
		if f.y < 0:
			name = "aria_back"            # vers le haut : dos
		elif f.x != 0:
			name = "aria_side"            # latéral : profil (miroir si gauche)
			flip = f.x < 0
		# vers le bas (ou par défaut) : "aria" (face), inchangé
	return { "name": name, "flip": flip }

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
