## Rendu du terrain "open world" par tuiles, biome-thématique, avec brouillard
## de guerre et caméra (culling au viewport). Repli ASCII si une texture manque.
extends Node2D

const CELL := 32          # taille native des tuiles (assets 32x32)
const COLOR_FLOOR := Color(0.12, 0.13, 0.10)
const COLOR_GLYPH := Color(0.30, 0.34, 0.28)
const COLOR_STAIRS := Color(1.0, 0.85, 0.3)
const COLOR_FOG := Color(0.015, 0.012, 0.028)        # non exploré (quasi noir, façon Moonring)
const COLOR_MEMORY := Color(0.015, 0.012, 0.028, 0.62) # exploré mais hors vision

# --- Ambiance "Les Strates" (inspiration Moonring) ----------------------------
# Halo de torche autour de l'héroïne + vignette de bord : concentrent le regard
# et donnent une atmosphère de donjon. Tout est dessiné en surimpression à la
# fin de _draw(), à partir de textures radiales générées une seule fois.
const POOL_TINT := Color(0.016, 0.012, 0.040)     # teinte froide du pool de torche
const POOL_MAX_A := 0.34                           # assombrissement max au bord de vision
const GLOW_TINT := Color(1.0, 0.88, 0.66)         # halo chaud près de l'héroïne
const GLOW_MAX_A := 0.13
const VIGNETTE_MAX_A := 0.55

var dungeon: Dungeon = null
var entities: Array = []
var loot: Array = []
var hazards: Array = []            # pièges au sol (dessinés comme glyphes discrets)
var reveal_loot: bool = false      # Œil du Devin : montre le butin à travers le brouillard
var tex: Dictionary = {}
var view_size: Vector2 = Vector2(896, 570)        # zone de jeu visible (réglée par Main)
var _font: Font
var _font_size := 18
var _pool_tex: ImageTexture = null
var _glow_tex: ImageTexture = null
var _vignette_tex: ImageTexture = null

# --- Couche d'animation/feedback (idle / attack / death) ----------------------
# Découplée de la logique : Main appelle fx_attack/fx_hit/fx_death ; le rendu lit
# ces effets transitoires dans _draw, animés par _process. Aucune incidence
# sur l'état de jeu — purement cosmétique.
const FX_ATTACK_DUR := 0.18
const FX_HIT_DUR := 0.22
const FX_DEATH_DUR := 0.38
const IDLE_AMP := 1.1
var _anim_t: float = 0.0
var _fx: Dictionary = {}        # instance_id -> { attack:{t,dir}, hit:{t} }
var _dying: Array = []          # [{ name, flip, glyph, color, x, y, t }] (fondus de mort)

func _ready() -> void:
	_font = ThemeDB.fallback_font
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_load_textures()
	_build_atmosphere_textures()

## Pré-calcule les textures d'ambiance (pool de torche + halo chaud). La vignette
## dépend de la taille de zone de jeu : elle est créée paresseusement dans _draw.
func _build_atmosphere_textures() -> void:
	# Pool : clair au centre -> assombri vers le bord de vision, puis ré-estompé
	# à 0 sur le tout dernier anneau (alpha nul au bord du carré => aucun bord net).
	_pool_tex = _make_pool(192)
	# Halo chaud : chaud au centre -> transparent au bord.
	_glow_tex = _make_radial(96, _alpha(GLOW_TINT, GLOW_MAX_A), _alpha(GLOW_TINT, 0.0), 0.0, 2.0)

## Texture du pool de torche : alpha = 0 au centre, croît en s'éloignant, puis
## redescend à 0 sur l'anneau extérieur — pas de transition dure au bord du carré.
func _make_pool(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d: float = clampf(Vector2(x - c, y - c).length() / c, 0.0, 1.0)
			var edge_fade: float = clampf((1.0 - d) / 0.18, 0.0, 1.0)
			var a: float = POOL_MAX_A * pow(d, 2.0) * edge_fade
			img.set_pixel(x, y, Color(POOL_TINT.r, POOL_TINT.g, POOL_TINT.b, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

## Renvoie `c` avec une nouvelle composante alpha (Color n'a pas de with_a en 4.x).
func _alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)

func _load_textures() -> void:
	var names := ["stairs", "aria", "aria_back", "aria_side", "knight", "mage", "ranger",
		"gobelin", "loup", "squelette", "orc", "spectre", "boss",
		"arme", "armure", "relique", "artifact", "potion", "road",
		# Nouveaux monstres (Pass 1)
		"araignee", "sanglier", "chauvesouris", "serpent", "ours",
		"zombie", "dullahan", "liche", "banshee", "revenant",
		"brigand", "gnoll", "troll", "kobold", "cultiste",
		"elementaire_feu", "golem", "fee", "drake", "mimic", "coffre",
		# Boss (Pass 2) + gardiens liés
		"roi_liche", "seigneur_fantome", "wyrm", "araignee_mere", "troll_ancestral",
		"paladin_dechu", "sorciere", "bourreau", "oeil_neant", "dieu_bete",
		"ame", "chaudron"]
	for b in Data.BIOMES:
		for role in ["ground", "tree", "rock", "water", "decor"]:
			names.append(Data.biome_sprite(b["id"], role))
	for n in names:
		var path := "res://assets/%s.png" % n
		if ResourceLoader.exists(path):
			tex[n] = load(path)

func refresh(d: Dungeon, ents: Array, loot_items: Array, hazard_items: Array = []) -> void:
	dungeon = d
	entities = ents
	loot = loot_items
	hazards = hazard_items
	queue_redraw()

# --- Animation/feedback : pilotage temps réel ---------------------------------
func _process(delta: float) -> void:
	if dungeon == null:
		return
	_anim_t += delta
	# Purge des effets transitoires expirés.
	for k in _fx.keys():
		var f: Dictionary = _fx[k]
		if f.has("attack") and _anim_t - float(f["attack"]["t"]) > FX_ATTACK_DUR:
			f.erase("attack")
		if f.has("hit") and _anim_t - float(f["hit"]["t"]) > FX_HIT_DUR:
			f.erase("hit")
		if f.is_empty():
			_fx.erase(k)
	var kept: Array = []
	for d in _dying:
		if _anim_t - float(d["t"]) <= FX_DEATH_DUR:
			kept.append(d)
	_dying = kept
	queue_redraw()

## Petit bond d'attaque vers la cible.
func fx_attack(e, target_pos: Vector2i) -> void:
	if e == null:
		return
	var dir := Vector2.ZERO
	var d: Vector2i = target_pos - e.pos()
	if d != Vector2i.ZERO:
		dir = Vector2(d).normalized()
	_fx_for(e.get_instance_id())["attack"] = { "t": _anim_t, "dir": dir }

## Flash blanc « touché ».
func fx_hit(e) -> void:
	if e == null:
		return
	_fx_for(e.get_instance_id())["hit"] = { "t": _anim_t }

## Capture l'entité mourante pour un fondu indépendant (elle quitte la liste).
func fx_death(e) -> void:
	if e == null:
		return
	var dv: Dictionary = _directional_sprite(e)
	_dying.append({ "name": dv["name"], "flip": dv["flip"], "glyph": e.glyph,
		"color": e.color, "x": e.x, "y": e.y, "t": _anim_t })

func _fx_for(id: int) -> Dictionary:
	if not _fx.has(id):
		_fx[id] = {}
	return _fx[id]

## Décalage visuel d'une entité : bob d'idle + bond d'attaque.
func _entity_offset(e) -> Vector2:
	var off := Vector2(0.0, sin(_anim_t * 3.2 + float(e.x * 7 + e.y * 13)) * IDLE_AMP)
	var f: Dictionary = _fx.get(e.get_instance_id(), {})
	if f.has("attack"):
		var p: float = clampf((_anim_t - float(f["attack"]["t"])) / FX_ATTACK_DUR, 0.0, 1.0)
		var dir: Vector2 = f["attack"]["dir"]
		off += dir * (sin(p * PI) * CELL * 0.34)
	return off

## Intensité du flash « touché » (0 = aucun).
func _entity_flash(e) -> float:
	var f: Dictionary = _fx.get(e.get_instance_id(), {})
	if f.has("hit"):
		return 1.0 - clampf((_anim_t - float(f["hit"]["t"])) / FX_HIT_DUR, 0.0, 1.0)
	return 0.0

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

	# --- Surbrillances de combat ---
	var player_entity = null
	for e in entities:
		if e.faction == Entity.Faction.PLAYER and e.is_alive():
			player_entity = e
			break
	if player_entity != null and dungeon.is_visible(player_entity.x, player_entity.y):
		var pcell := _cell_rect(player_entity.x, player_entity.y)
		draw_rect(pcell, Color(0.4, 0.8, 1.0, 0.12), true)
		draw_rect(pcell, Color(0.4, 0.9, 1.0, 0.45), false)
		for e in entities:
			if e.faction == Entity.Faction.ENEMY and e.is_alive() and dungeon.is_visible(e.x, e.y):
				var dx := absi(e.x - player_entity.x)
				var dy := absi(e.y - player_entity.y)
				var dist := maxi(dx, dy)
				var ecell := _cell_rect(e.x, e.y)
				if dist == 1:
					draw_rect(ecell, Color(1.0, 0.25, 0.15, 0.22), true)
					draw_rect(ecell, Color(1.0, 0.35, 0.2, 0.75), false)
				elif dist <= 3:
					draw_rect(ecell, Color(0.9, 0.55, 0.15, 0.08), true)

	# Pièges au sol : visibles uniquement dans le champ de vision actuel.
	for hz in hazards:
		var hp: Vector2i = hz["pos"]
		if dungeon.is_visible(hp.x, hp.y):
			_draw_glyph(hp.x, hp.y, str(hz.get("glyph", "^")), hz.get("color", Color(0.95, 0.55, 0.45)))

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
	# Fondus de mort (entités déjà retirées de la liste, animées indépendamment).
	for d in _dying:
		if not dungeon.is_visible(int(d["x"]), int(d["y"])):
			continue
		var dp: float = clampf((_anim_t - float(d["t"])) / FX_DEATH_DUR, 0.0, 1.0)
		var dr: Rect2 = _cell_rect(int(d["x"]), int(d["y"]))
		dr.position.y -= dp * CELL * 0.4
		if tex.has(d["name"]):
			if d["flip"]:
				dr = Rect2(dr.position.x + dr.size.x, dr.position.y, -dr.size.x, dr.size.y)
			draw_texture_rect(tex[d["name"]], dr, false, Color(1, 1, 1, 1.0 - dp))

	for e in entities:
		if e.is_alive() and dungeon.is_visible(e.x, e.y):
			var dv: Dictionary = _directional_sprite(e)
			var off: Vector2 = _entity_offset(e)
			if not _blit_ex_off(dv["name"], e.x, e.y, dv["flip"], off):
				_draw_glyph(e.x, e.y, e.glyph, e.color)
			var flash: float = _entity_flash(e)
			if flash > 0.0:
				draw_rect(_cell_rect(e.x, e.y), Color(1, 1, 1, 0.55 * flash), true)
			_draw_hp_pip(e)

	_draw_atmosphere()

## Surimpression d'ambiance : pool de torche + halo chaud centrés sur l'héroïne,
## puis vignette de bord couvrant la zone de jeu. Dessinés en dernier (au-dessus
## du terrain et des entités) pour focaliser le regard façon Moonring.
func _draw_atmosphere() -> void:
	var origin: Vector2 = -position
	# Vignette créée à la demande (dépend de la taille de zone de jeu).
	if _vignette_tex == null and view_size.x > 1.0 and view_size.y > 1.0:
		_vignette_tex = _make_vignette(maxi(8, int(view_size.x / 3.0)), maxi(8, int(view_size.y / 3.0)))
	# Pool + halo autour de l'héroïne (si visible).
	var pl = null
	for e in entities:
		if e.faction == Entity.Faction.PLAYER and e.is_alive():
			pl = e
			break
	if pl != null and dungeon.is_visible(pl.x, pl.y):
		var hc := Vector2(pl.x * CELL + CELL * 0.5, pl.y * CELL + CELL * 0.5)
		if _pool_tex != null:
			var rad := float((pl.vision + 2) * CELL)
			draw_texture_rect(_pool_tex, Rect2(hc - Vector2(rad, rad), Vector2(rad * 2.0, rad * 2.0)), false)
		if _glow_tex != null:
			var gr := float(CELL) * 3.2
			draw_texture_rect(_glow_tex, Rect2(hc - Vector2(gr, gr), Vector2(gr * 2.0, gr * 2.0)), false)
	if _vignette_tex != null:
		draw_texture_rect(_vignette_tex, Rect2(origin, view_size), false)

## Texture radiale (carrée) : couleur `inner` au centre -> `outer` au bord, avec
## un palier `inner_stop` (zone centrale plate) et une courbe d'exposant `expo`.
func _make_radial(size: int, inner: Color, outer: Color, inner_stop: float, expo: float) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d: float = clampf(Vector2(x - c, y - c).length() / c, 0.0, 1.0)
			var t: float = 0.0
			if d > inner_stop and inner_stop < 1.0:
				t = pow((d - inner_stop) / (1.0 - inner_stop), expo)
			img.set_pixel(x, y, inner.lerp(outer, clampf(t, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

## Vignette rectangulaire : transparente au centre, sombre vers les bords.
func _make_vignette(w: int, h: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cx := (w - 1) * 0.5
	var cy := (h - 1) * 0.5
	for y in h:
		for x in w:
			var nx: float = abs(x - cx) / cx
			var ny: float = abs(y - cy) / cy
			var e: float = maxf(nx, ny)
			var a: float = 0.0
			if e > 0.58:
				a = pow((e - 0.58) / 0.42, 2.2) * VIGNETTE_MAX_A
			img.set_pixel(x, y, Color(0.0, 0.0, 0.0, clampf(a, 0.0, VIGNETTE_MAX_A)))
	return ImageTexture.create_from_image(img)

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

## Variante de _blit_ex avec décalage visuel (bob d'idle / bond d'attaque).
func _blit_ex_off(name: String, gx: int, gy: int, flip: bool, off: Vector2) -> bool:
	if name == "" or not tex.has(name):
		return false
	var r: Rect2 = _cell_rect(gx, gy)
	r.position += off
	if flip:
		r = Rect2(r.position.x + r.size.x, r.position.y, -r.size.x, r.size.y)
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
	var by := e.y * CELL + CELL - 4.0
	# Séparateur sombre 1px au-dessus de la barre.
	draw_rect(Rect2(Vector2(bx, by - 1), Vector2(bar_w, 1)), Color(0.0, 0.0, 0.0, 0.6), true)
	draw_rect(Rect2(Vector2(bx, by), Vector2(bar_w, 4)), Color(0.15, 0.03, 0.03), true)
	var col := Color(0.3, 0.85, 0.3) if e.faction == Entity.Faction.PLAYER else Color(0.85, 0.3, 0.3)
	draw_rect(Rect2(Vector2(bx, by), Vector2(bar_w * ratio, 4)), col, true)
