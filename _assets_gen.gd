extends SceneTree
# Générateur d'assets pixel-art — IDENTITÉ VISUELLE "Les Strates".
# Refonte façon Moonring : palette restreinte med-fantasy NÉON, silhouettes
# lisibles, contour quasi-noir cohérent, lumière en haut-gauche, halos néon
# (glow/bloom) sur les éléments magiques et dithering rétro (Bayer) sur les sols.
# Lancé en headless : godot --headless --script res://_assets_gen.gd
# Produit des PNG 24x24 dans res://assets/.
#
# NOTE : ce script et le moteur de rendu hors-ligne (outils de dev) partagent la
# même logique ; les PNG livrés dans assets/ doivent rester cohérents avec lui.

const TILE := 24
var rng := RandomNumberGenerator.new()

# --- PALETTE D'IDENTITÉ -------------------------------------------------------
const INK      := Color(0.055, 0.050, 0.090)   # contour quasi-noir (indigo profond)
const INK_SOFT := Color(0.105, 0.098, 0.160)
const STONE    := Color(0.227, 0.212, 0.306)
const STONE_D  := Color(0.149, 0.137, 0.212)
const STONE_L  := Color(0.34, 0.32, 0.46)
const FLOOR_A  := Color(0.090, 0.084, 0.135)
const FLOOR_B  := Color(0.140, 0.130, 0.200)
const STEEL    := Color(0.588, 0.627, 0.725)
const STEEL_D  := Color(0.361, 0.392, 0.490)
const STEEL_L  := Color(0.82, 0.86, 0.95)
const BONE     := Color(0.880, 0.866, 0.780)
const BONE_D   := Color(0.60, 0.58, 0.49)
const GOLD     := Color(0.953, 0.749, 0.286)
const GOLD_D   := Color(0.588, 0.431, 0.137)
const GOLD_L   := Color(1.0, 0.92, 0.55)
const BLOOD    := Color(0.812, 0.231, 0.251)
const BLOOD_D  := Color(0.49, 0.13, 0.16)
const ARCANE   := Color(0.643, 0.404, 0.918)
const ARCANE_L := Color(0.835, 0.643, 1.0)
const CYAN     := Color(0.392, 0.882, 0.925)
const CYAN_L   := Color(0.69, 0.99, 1.0)
const POISON   := Color(0.510, 0.851, 0.376)
const EMBER    := Color(1.0, 0.580, 0.220)
const EMBER_L  := Color(1.0, 0.80, 0.42)

# Bayer 4x4 (valeurs 0..15) pour le dithering rétro façon CGA.
const BAYER4 := [
	[0, 8, 2, 10],
	[12, 4, 14, 6],
	[3, 11, 1, 9],
	[15, 7, 13, 5],
]

func _init() -> void:
	rng.seed = 1337
	DirAccess.make_dir_recursive_absolute("res://assets")

	# --- Textures du monde ---
	_save(_gen_floor(), "floor")
	_save(_gen_wall(), "wall")
	_save(_gen_stairs(), "stairs")

	# --- Héroïne (sprite dédié, 3 vues directionnelles) + classes legacy ---
	_save(_gen_creature("aria"), "aria")            # face (bas)
	_save(_gen_creature("aria_back"), "aria_back")  # dos (haut)
	_save(_gen_creature("aria_side"), "aria_side")  # profil droite (miroir à gauche)
	_save(_gen_creature("knight"), "knight")
	_save(_gen_creature("mage"), "mage")
	_save(_gen_creature("ranger"), "ranger")

	# --- Ennemis ---
	_save(_gen_creature("gobelin"), "gobelin")
	_save(_gen_creature("loup"), "loup")
	_save(_gen_creature("squelette"), "squelette")
	_save(_gen_creature("orc"), "orc")
	_save(_gen_creature("spectre"), "spectre")
	_save(_gen_creature("boss"), "boss")

	# --- Butin ---
	_save(_gen_weapon(), "arme")
	_save(_gen_armor(), "armure")
	_save(_gen_relic(), "relique")
	_save(_gen_artifact(), "artifact")
	_save(_gen_potion(), "potion")

	# --- Icônes de la carte à embranchements ---
	_save(_gen_node_combat(), "node_combat")
	_save(_gen_node_boss(), "node_boss")
	_save(_gen_node_elite(), "node_elite")
	_save(_gen_node_shop(), "node_shop")
	_save(_gen_node_event(), "node_event")
	_save(_gen_node_rest(), "node_rest")

	# --- Terrain par biome (open world) ---
	for b in Data.BIOMES:
		var id: String = b["id"]
		_save(_gen_ground(b["ground_a"], b["ground_b"]), "%s_ground" % id)
		_save(_gen_tree(b["trunk"], b["leaf"], b["tree_style"]), "%s_tree" % id)
		_save(_gen_rock(b["rock"]), "%s_rock" % id)
		_save(_gen_water(b["water"]), "%s_water" % id)
		_save(_gen_decor(b["decor"], b["decor_style"]), "%s_decor" % id)
	_save(_gen_road(), "road")

	print("=== ASSETS GENERATED ===")
	quit()

# --- IO -----------------------------------------------------------------------
func _save(img: Image, name: String) -> void:
	img.save_png("res://assets/%s.png" % name)

func _new(opaque: bool = false) -> Image:
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	if opaque:
		img.fill(Color(0, 0, 0, 1))
	return img

# --- Primitives de dessin -----------------------------------------------------
func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and x < TILE and y >= 0 and y < TILE:
		if c.a >= 1.0:
			img.set_pixel(x, y, c)
		elif c.a > 0.0:
			img.set_pixel(x, y, img.get_pixel(x, y).lerp(c, c.a))

func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_px(img, xx, yy, c)

func _disc(img: Image, cx: int, cy: int, r: float, c: Color) -> void:
	_ellipse(img, cx, cy, r, r, c)

func _ellipse(img: Image, cx: int, cy: int, rx: float, ry: float, c: Color) -> void:
	for yy in range(int(cy - ry), int(cy + ry) + 1):
		for xx in range(int(cx - rx), int(cx + rx) + 1):
			var dx := (xx - cx) / rx
			var dy := (yy - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				_px(img, xx, yy, c)

# Disque avec contour : dessine d'abord le contour (r+1) puis le remplissage.
func _disc_o(img: Image, cx: int, cy: int, r: float, c: Color, oc: Color = INK) -> void:
	_disc(img, cx, cy, r + 1.0, oc)
	_disc(img, cx, cy, r, c)

# Trapèze vertical (silhouette de corps/cape), pointe étroite en haut.
func _trapezoid(img: Image, cx: int, top_y: int, bot_y: int, top_hw: float, bot_hw: float, c: Color) -> void:
	var span: int = max(1, bot_y - top_y)
	for i in range(span + 1):
		var t := float(i) / float(span)
		var hw := int(round(lerp(top_hw, bot_hw, t)))
		var y := top_y + i
		for x in range(cx - hw, cx + hw + 1):
			_px(img, x, y, c)

# Trapèze avec contour sombre.
func _trapezoid_o(img: Image, cx: int, top_y: int, bot_y: int, top_hw: float, bot_hw: float, c: Color, oc: Color = INK) -> void:
	_trapezoid(img, cx, top_y - 1, bot_y + 1, top_hw + 1.0, bot_hw + 1.0, oc)
	_trapezoid(img, cx, top_y, bot_y, top_hw, bot_hw, c)

# Segment 1px (Bresenham) — utilisé pour les lames diagonales des icônes.
func _line(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	var dx: int = absi(x1 - x0)
	var dy: int = -absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy
	var x: int = x0
	var y: int = y0
	while true:
		_px(img, x, y, c)
		if x == x1 and y == y1:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy

# Triangle plein, pointe vers le haut, base en bas.
func _tri_up(img: Image, cx: int, base_y: int, half_w: int, height: int, c: Color) -> void:
	for i in range(height):
		var w := int(round(half_w * (1.0 - float(i) / float(height))))
		var yy := base_y - i
		for xx in range(cx - w, cx + w + 1):
			_px(img, xx, yy, c)

# Losange (gemme / éclat).
func _diamond(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for dy in range(-r, r + 1):
		var w: int = r - absi(dy)
		for dx in range(-w, w + 1):
			_px(img, cx + dx, cy + dy, c)

# Halo néon additif (bloom) : éclaircit le fond et lui donne un peu d'alpha.
func _glow(img: Image, cx: float, cy: float, r: float, c: Color, strength: float = 0.85) -> void:
	for yy in range(int(floor(cy - r)), int(ceil(cy + r)) + 1):
		for xx in range(int(floor(cx - r)), int(ceil(cx + r)) + 1):
			if xx < 0 or xx >= TILE or yy < 0 or yy >= TILE:
				continue
			var d := sqrt(pow(xx - cx, 2.0) + pow(yy - cy, 2.0)) / r
			if d >= 1.0:
				continue
			var fa := (1.0 - d) * (1.0 - d) * strength
			var p := img.get_pixel(xx, yy)
			p.r = min(1.0, p.r + c.r * fa)
			p.g = min(1.0, p.g + c.g * fa)
			p.b = min(1.0, p.b + c.b * fa)
			p.a = min(1.0, p.a + (1.0 - p.a) * fa * c.a)
			img.set_pixel(xx, yy, p)

# Ombre de contact douce au pied d'une figure (ancre la silhouette au sol).
func _ground_shadow(img: Image) -> void:
	_ellipse(img, 12, 21, 6.5, 1.8, Color(INK.r, INK.g, INK.b, 0.34))

func _fade(img: Image, a: float) -> void:
	for y in TILE:
		for x in TILE:
			var c := img.get_pixel(x, y)
			if c.a > 0.0:
				c.a *= a
				img.set_pixel(x, y, c)

# --- Textures du monde --------------------------------------------------------
func _gen_floor() -> Image:
	var img := _new(true)
	img.fill(FLOOR_A)
	for y in TILE:
		for x in TILE:
			var r := rng.randf()
			if r < 0.10:
				_px(img, x, y, FLOOR_A.darkened(0.25))
			elif r > 0.92:
				_px(img, x, y, FLOOR_B)
	for i in TILE:
		_px(img, i, 0, INK)
		_px(img, 0, i, INK)
		_px(img, i, 12, INK_SOFT.darkened(0.1))
		_px(img, 12, i, INK_SOFT.darkened(0.1))
	_px(img, 2, 2, FLOOR_B.lightened(0.12))
	_px(img, 14, 2, FLOOR_B.lightened(0.12))
	return img

func _gen_wall() -> Image:
	var img := _new(true)
	img.fill(STONE)
	var brick_h := 6
	var brick_w := 8
	var row := 0
	for by in range(0, TILE, brick_h):
		for x in TILE:
			_px(img, x, by,     INK)
			_px(img, x, by + 1, INK.lerp(STONE_D, 0.4))
			if by + 2 < TILE:
				_px(img, x, by + 2, STONE_L)
		var off := (brick_w / 2) if (row % 2 == 1) else 0
		var bx := -off
		while bx <= TILE:
			for yy in range(by + 2, by + brick_h):
				_px(img, bx,     yy, INK)
				_px(img, bx + 1, yy, INK.lerp(STONE_D, 0.4))
			var face_col := STONE_L if (row % 2 == 0) else STONE
			for yy in range(by + 3, by + brick_h - 1):
				for xx in range(bx + 2, bx + brick_w - 1):
					if xx >= 0 and xx < TILE and yy >= 0 and yy < TILE:
						_px(img, xx, yy, face_col)
			for yy in range(by + 2, by + brick_h):
				_px(img, bx + brick_w - 1, yy, STONE_D)
			bx += brick_w
		row += 1
	for i in 18:
		_px(img, rng.randi_range(0, TILE - 1), rng.randi_range(0, TILE - 1), STONE_D)
	# Cristaux arcaniques en positions fixes, halo néon.
	var crystal_pos := [Vector2i(5, 4), Vector2i(17, 10), Vector2i(3, 16), Vector2i(19, 3)]
	for cp in crystal_pos:
		_glow(img, cp.x, cp.y, 2.4, ARCANE, 0.55)
		_px(img, cp.x,     cp.y,     ARCANE)
		_px(img, cp.x,     cp.y - 1, ARCANE_L)
		_px(img, cp.x - 1, cp.y,     ARCANE.darkened(0.3))
	return img

func _gen_stairs() -> Image:
	var img := _new(false)                        # transparent : posé sur le sol
	_disc_o(img, 12, 13, 9.0, INK_SOFT, INK)      # masse de l'arche
	_glow(img, 12, 14, 9.0, ARCANE, 0.55)
	_ellipse(img, 12, 14, 6.5, 7.5, Color(ARCANE.r, ARCANE.g, ARCANE.b, 0.55))
	_ellipse(img, 12, 15, 4.5, 5.5, Color(ARCANE_L.r, ARCANE_L.g, ARCANE_L.b, 0.6))
	for s in range(3):
		var y := 19 - s * 3
		var w := 5 - s
		_rect(img, 12 - w, y, w * 2, 1, Color(CYAN_L.r, CYAN_L.g, CYAN_L.b, 0.75))
	_glow(img, 12, 10, 4.0, GOLD_L, 0.7)
	_tri_up(img, 12, 9, 4, 4, GOLD_L)
	_tri_up(img, 12, 11, 4, 3, GOLD)
	return img

# --- Créatures (héroïne & ennemis) -------------------------------------------
func _gen_creature(kind: String) -> Image:
	var img := _new(false)
	match kind:
		"aria":      _fig_aria(img)
		"aria_back": _fig_aria_back(img)
		"aria_side": _fig_aria_side(img)
		"knight":  _fig_knight(img)
		"mage":    _fig_mage(img)
		"ranger":  _fig_ranger(img)
		"gobelin": _fig_gobelin(img)
		"loup":    _fig_wolf(img)
		"squelette": _fig_skeleton(img)
		"orc":     _fig_orc(img)
		"spectre": _fig_spectre(img)
		"boss":    _fig_boss(img)
		_:         _fig_knight(img)
	return img

# Reflet d'œil lumineux générique, avec halo néon.
func _glow_eyes(img: Image, cx: int, ey: int, c: Color, spread: int = 3) -> void:
	_glow(img, cx - spread + 0.5, ey + 0.5, 2.0, c, 0.7)
	_glow(img, cx + spread - 0.5, ey + 0.5, 2.0, c, 0.7)
	_rect(img, cx - spread, ey, 2, 2, c)
	_rect(img, cx + spread - 1, ey, 2, 2, c)
	_px(img, cx - spread, ey, c.lightened(0.45))
	_px(img, cx + spread, ey, c.lightened(0.45))

const ROSE   := Color(0.95, 0.57, 0.87)
const ROSE_D := Color(0.62, 0.30, 0.56)
const ROSE_L := Color(1.0, 0.78, 0.97)
const SKIN   := Color(0.95, 0.83, 0.73)
const SKIN_D := Color(0.78, 0.62, 0.54)

# --- Vue de FACE (déplacement vers le bas / par défaut) ---
func _fig_aria(img: Image) -> void:
	_ground_shadow(img)
	_trapezoid(img, 12, 11, 21, 3.6, 6.0, ARCANE.darkened(0.4))
	_rect(img, 9, 18, 3, 4, STEEL_D); _rect(img, 9, 18, 3, 1, STEEL)
	_rect(img, 13, 18, 3, 4, STEEL_D); _rect(img, 13, 18, 3, 1, STEEL)
	_trapezoid_o(img, 12, 15, 20, 2.6, 4.0, ARCANE.darkened(0.25))
	_rect(img, 12, 16, 1, 4, ARCANE_L.darkened(0.1))
	_trapezoid_o(img, 12, 10, 16, 3.2, 3.6, STEEL_D)
	_trapezoid(img, 12, 11, 15, 2.4, 2.8, STEEL_L)
	_rect(img, 10, 11, 5, 1, CYAN)
	_glow(img, 12, 13, 2.6, CYAN, 0.6)
	_diamond(img, 12, 13, 2, CYAN); _px(img, 12, 13, Color(1, 1, 1))
	_disc_o(img, 8, 11, 1.7, STEEL, STEEL_D); _disc_o(img, 16, 11, 1.7, STEEL, STEEL_D)
	_rect(img, 7, 12, 2, 4, ARCANE.darkened(0.1))
	_rect(img, 15, 12, 2, 4, ARCANE.darkened(0.1))
	_px(img, 7, 15, SKIN); _px(img, 16, 15, SKIN)
	_disc_o(img, 12, 7, 3.7, ROSE_D, INK)
	_ellipse(img, 12, 8, 2.5, 2.7, SKIN)
	_rect(img, 9, 7, 2, 4, ROSE); _rect(img, 14, 7, 2, 4, ROSE)
	_px(img, 9, 7, ROSE_L)
	_rect(img, 9, 5, 7, 2, ROSE); _px(img, 10, 5, ROSE_L)
	_rect(img, 10, 7, 5, 1, ROSE_D)
	_px(img, 11, 9, INK); _px(img, 14, 9, INK)
	_px(img, 11, 8, SKIN_D); _px(img, 14, 8, SKIN_D)
	_px(img, 12, 11, SKIN_D)
	_rect(img, 10, 6, 5, 1, GOLD); _glow(img, 12, 6, 1.6, CYAN_L, 0.7); _px(img, 12, 6, CYAN_L)

# --- Vue de DOS (déplacement vers le haut) ---
func _fig_aria_back(img: Image) -> void:
	_ground_shadow(img)
	_rect(img, 9, 18, 3, 4, STEEL_D); _rect(img, 13, 18, 3, 4, STEEL_D)
	_trapezoid_o(img, 12, 9, 22, 3.6, 7.5, ARCANE.darkened(0.45))
	_trapezoid(img, 12, 10, 21, 2.8, 6.0, ARCANE)
	_rect(img, 12, 10, 1, 11, ARCANE_L.darkened(0.12))
	_px(img, 9, 13, ARCANE_L.darkened(0.2)); _px(img, 15, 16, ARCANE_L.darkened(0.2))
	_disc_o(img, 8, 11, 1.7, STEEL, STEEL_D); _disc_o(img, 16, 11, 1.7, STEEL, STEEL_D)
	_rect(img, 9, 10, 6, 1, CYAN)
	_disc_o(img, 12, 7, 3.7, ROSE_D, INK)
	_disc(img, 12, 7, 3.1, ROSE)
	_ellipse(img, 10, 5, 1.4, 1.2, ROSE_L)
	_rect(img, 11, 9, 2, 8, ROSE_D); _rect(img, 11, 9, 2, 7, ROSE)
	_px(img, 11, 12, ROSE_L); _px(img, 12, 15, ROSE_D)
	_rect(img, 9, 6, 6, 1, GOLD)

# --- Vue de PROFIL (orientée vers la DROITE, miroir à gauche) ---
func _fig_aria_side(img: Image) -> void:
	_ground_shadow(img)
	_trapezoid(img, 9, 11, 21, 2.4, 5.2, ARCANE.darkened(0.45))
	_trapezoid(img, 9, 12, 20, 1.7, 4.0, ARCANE.darkened(0.2))
	_px(img, 5, 20, ARCANE.darkened(0.3))
	_rect(img, 11, 18, 3, 4, STEEL_D); _rect(img, 11, 18, 3, 1, STEEL)
	_rect(img, 13, 19, 3, 3, STEEL_D.darkened(0.08))
	_trapezoid_o(img, 12, 10, 17, 2.4, 3.0, STEEL_D)
	_trapezoid(img, 12, 11, 16, 1.7, 2.2, STEEL_L)
	_rect(img, 13, 12, 3, 1, CYAN)
	_disc_o(img, 11, 11, 1.7, STEEL, STEEL_D)
	_rect(img, 14, 12, 2, 4, ARCANE.darkened(0.1))
	_px(img, 15, 15, SKIN)
	_trapezoid_o(img, 9, 9, 19, 1.2, 1.8, ROSE_D)
	_trapezoid(img, 9, 9, 18, 0.7, 1.2, ROSE)
	_px(img, 9, 13, ROSE_L); _px(img, 9, 17, ROSE_D)
	_disc_o(img, 12, 7, 3.6, ROSE_D, INK)
	_disc(img, 11, 6, 3.0, ROSE)
	_ellipse(img, 10, 5, 1.2, 1.0, ROSE_L)
	_ellipse(img, 14, 8, 2.1, 2.3, SKIN)
	_px(img, 16, 8, SKIN_D)
	_rect(img, 14, 8, 1, 2, INK)
	_px(img, 15, 11, SKIN_D)
	_px(img, 13, 5, ROSE); _px(img, 14, 6, ROSE)
	_px(img, 12, 5, GOLD); _px(img, 13, 6, GOLD); _glow(img, 14, 7, 1.4, CYAN_L, 0.7); _px(img, 14, 7, CYAN_L)

# Classe « chevalier » (legacy) : armure d'acier, écharpe rouge, visière cyan.
func _fig_knight(img: Image) -> void:
	_ground_shadow(img)
	_trapezoid_o(img, 12, 11, 21, 2.5, 6.0, STEEL_D)
	_trapezoid(img, 12, 12, 20, 1.5, 4.5, STEEL)
	_rect(img, 6, 12, 3, 2, BLOOD)
	_px(img, 5, 13, BLOOD_D)
	_px(img, 8, 11, BLOOD)
	_rect(img, 10, 13, 4, 5, STEEL_L)
	_px(img, 10, 13, STEEL)
	_rect(img, 11, 14, 1, 3, Color(1, 1, 1, 0.55))
	_disc_o(img, 12, 7, 4.2, STEEL_D, INK)
	_disc(img, 12, 6, 3.4, STEEL)
	_ellipse(img, 10, 5, 1.6, 1.4, STEEL_L)
	_glow(img, 12, 7, 3.4, CYAN, 0.4)
	_rect(img, 9, 7, 6, 1, CYAN_L)
	_px(img, 9, 7, CYAN)
	_tri_up(img, 12, 3, 1, 3, BLOOD)
	_rect(img, 17, 9, 1, 9, STEEL_L)
	_rect(img, 16, 16, 3, 1, GOLD)

func _fig_mage(img: Image) -> void:
	_ground_shadow(img)
	_trapezoid_o(img, 12, 11, 21, 2.0, 6.5, ARCANE.darkened(0.45))
	_trapezoid(img, 12, 12, 20, 1.2, 5.0, ARCANE)
	_rect(img, 11, 14, 2, 6, ARCANE_L.darkened(0.1))
	_disc_o(img, 12, 8, 3.4, ARCANE.darkened(0.4), INK)
	_disc(img, 12, 8, 2.6, Color(0.86, 0.78, 0.66))
	_glow_eyes(img, 12, 7, CYAN, 2)
	_trapezoid_o(img, 12, 1, 6, 0.5, 4.5, ARCANE.darkened(0.25))
	_glow(img, 12, 1, 2.0, GOLD_L, 0.8); _px(img, 12, 1, GOLD_L)
	_px(img, 9, 6, GOLD)
	_rect(img, 6, 8, 1, 12, GOLD_D)
	_glow(img, 6, 7, 3.0, CYAN, 0.7)
	_disc_o(img, 6, 7, 2.0, CYAN, INK)
	_px(img, 6, 6, CYAN_L)

func _fig_ranger(img: Image) -> void:
	_ground_shadow(img)
	_trapezoid_o(img, 12, 11, 21, 2.5, 6.0, POISON.darkened(0.5))
	_trapezoid(img, 12, 12, 20, 1.6, 4.6, POISON.darkened(0.25))
	_rect(img, 11, 14, 2, 5, POISON.darkened(0.1))
	_disc_o(img, 12, 7, 4.2, POISON.darkened(0.5), INK)
	_ellipse(img, 12, 6, 3.4, 3.6, POISON.darkened(0.3))
	_ellipse(img, 12, 8, 2.4, 2.0, Color(0.07, 0.07, 0.10))
	_glow_eyes(img, 12, 8, CYAN_L, 2)
	for i in range(11):
		var yy := 6 + i
		var dx := int(round(3.0 * sin(float(i) / 10.0 * PI)))
		_px(img, 18 - dx, yy, GOLD_D)
	_rect(img, 18, 6, 1, 11, Color(0.85, 0.85, 0.9, 0.8))

func _fig_gobelin(img: Image) -> void:
	_ground_shadow(img)
	var skin := POISON.darkened(0.15)
	_trapezoid_o(img, 12, 13, 21, 3.0, 5.5, skin.darkened(0.35))
	_trapezoid(img, 12, 14, 20, 2.0, 4.2, skin)
	_rect(img, 10, 15, 4, 3, Color(0.45, 0.32, 0.22))
	_disc_o(img, 12, 9, 4.0, skin.darkened(0.3), INK)
	_disc(img, 12, 9, 3.2, skin)
	_ellipse(img, 10, 7, 1.3, 1.1, skin.lightened(0.28))
	_tri_up(img, 6, 11, 2, 5, skin.darkened(0.1))
	_tri_up(img, 18, 11, 2, 5, skin.darkened(0.1))
	_glow_eyes(img, 12, 8, GOLD_L, 2)
	_rect(img, 10, 11, 4, 1, INK)
	_px(img, 11, 11, BONE)
	_rect(img, 18, 13, 1, 5, STEEL_L)

func _fig_wolf(img: Image) -> void:
	_ground_shadow(img)
	var fur := Color(0.40, 0.42, 0.50)
	var fur_d := fur.darkened(0.42)
	var fur_l := fur.lightened(0.20)
	_ellipse(img, 14, 15, 7.5, 4.4, fur_d)
	_ellipse(img, 14, 15, 6.5, 3.6, fur)
	_ellipse(img, 17, 13, 3.4, 3.0, fur)
	_ellipse(img, 16, 12, 2.0, 1.4, fur_l)
	_rect(img, 9, 18, 2, 3, fur_d)
	_rect(img, 16, 18, 2, 3, fur_d)
	_ellipse(img, 21, 12, 2.6, 1.4, fur_d)
	_disc_o(img, 6, 13, 3.6, fur_d, INK)
	_disc(img, 6, 13, 2.9, fur)
	_tri_up(img, 4, 10, 1, 3, fur_d)
	_tri_up(img, 8, 10, 1, 3, fur_d)
	_rect(img, 1, 13, 4, 2, fur_l)
	_px(img, 1, 14, INK)
	_glow(img, 5.5, 12.5, 1.6, CYAN_L, 0.7)
	_rect(img, 5, 12, 2, 1, CYAN_L)
	_px(img, 4, 15, BONE)

func _fig_skeleton(img: Image) -> void:
	_ground_shadow(img)
	_trapezoid_o(img, 12, 12, 20, 2.0, 4.0, BONE_D)
	_trapezoid(img, 12, 13, 19, 1.4, 3.0, BONE)
	for ry in [14, 16, 18]:
		_rect(img, 10, ry, 5, 1, INK_SOFT)
	_rect(img, 12, 13, 1, 7, BONE_D)
	_disc_o(img, 12, 8, 4.0, BONE_D, INK)
	_disc(img, 12, 7, 3.3, BONE)
	_ellipse(img, 10, 6, 1.3, 1.1, Color(1, 1, 0.95))
	_rect(img, 9, 7, 2, 2, INK)
	_rect(img, 13, 7, 2, 2, INK)
	_glow(img, 9.5, 7.5, 1.6, CYAN, 0.7); _glow(img, 14.5, 7.5, 1.6, CYAN, 0.7)
	_px(img, 9, 7, CYAN)
	_px(img, 14, 7, CYAN)
	for tx in range(10, 15, 2):
		_px(img, tx, 10, INK)

func _fig_orc(img: Image) -> void:
	_ground_shadow(img)
	var skin := Color(0.30, 0.44, 0.30)
	var skin_l := skin.lightened(0.20)
	_trapezoid_o(img, 11, 10, 21, 5.0, 7.5, skin.darkened(0.45))
	_trapezoid(img, 11, 11, 20, 4.0, 6.0, skin)
	_rect(img, 6, 12, 10, 2, Color(0.36, 0.25, 0.18))
	_rect(img, 8, 15, 6, 3, skin_l)
	_disc_o(img, 11, 7, 4.6, skin.darkened(0.4), INK)
	_disc(img, 11, 7, 3.8, skin)
	_ellipse(img, 9, 5, 1.6, 1.3, skin_l)
	_rect(img, 7, 6, 9, 1, INK)
	_glow_eyes(img, 11, 7, BLOOD, 3)
	_tri_up(img, 9, 13, 1, 4, BONE)
	_tri_up(img, 13, 13, 1, 4, BONE)
	_rect(img, 9, 11, 5, 1, INK)
	_rect(img, 18, 5, 1, 15, Color(0.36, 0.25, 0.18))
	_rect(img, 14, 5, 5, 5, STEEL_D)
	_rect(img, 15, 6, 3, 3, STEEL)
	_rect(img, 15, 6, 3, 1, STEEL_L)
	_px(img, 14, 7, STEEL_L); _px(img, 14, 8, STEEL_L)

func _fig_spectre(img: Image) -> void:
	_glow(img, 12, 9, 6.5, ARCANE, 0.5)
	_disc_o(img, 12, 9, 5.0, ARCANE.darkened(0.35), INK_SOFT)
	_disc(img, 12, 9, 4.2, ARCANE.darkened(0.1))
	_trapezoid(img, 12, 11, 20, 3.5, 6.0, ARCANE.darkened(0.1))
	for x in range(6, 19):
		var cut := 20 - ((x % 3))
		for y in range(cut, TILE):
			_px(img, x, y, Color(0, 0, 0, 0))
	_ellipse(img, 12, 9, 2.6, 2.2, Color(0.06, 0.05, 0.10))
	_glow_eyes(img, 12, 8, CYAN_L, 2)
	_px(img, 12, 11, CYAN)
	_fade(img, 0.82)

func _fig_boss(img: Image) -> void:
	_ellipse(img, 12, 22, 8.0, 2.0, Color(INK.r, INK.g, INK.b, 0.40))
	_trapezoid_o(img, 12, 9, 22, 4.5, 8.5, INK_SOFT)
	_trapezoid(img, 12, 10, 21, 3.6, 7.0, Color(0.22, 0.12, 0.16))
	_rect(img, 11, 13, 2, 8, BLOOD_D)
	_rect(img, 8, 13, 8, 3, Color(0.30, 0.16, 0.20))
	_glow(img, 12, 14, 2.6, GOLD, 0.65)
	_disc_o(img, 12, 14, 2.0, GOLD, GOLD_D)
	_px(img, 12, 13, GOLD_L)
	_disc_o(img, 12, 7, 4.6, INK_SOFT, INK)
	_disc(img, 12, 7, 3.8, Color(0.26, 0.16, 0.20))
	_tri_up(img, 6, 6, 2, 6, BONE_D)
	_tri_up(img, 18, 6, 2, 6, BONE_D)
	_px(img, 6, 0, BONE); _px(img, 18, 0, BONE)
	_glow_eyes(img, 12, 7, EMBER, 3)
	_px(img, 9, 7, GOLD_L); _px(img, 15, 7, GOLD_L)
	_rect(img, 10, 10, 5, 1, INK)

# --- Butin --------------------------------------------------------------------
func _gen_weapon() -> Image:
	var img := _new(false)
	_rect(img, 10, 3, 4, 13, INK)
	_rect(img, 11, 4, 2, 11, STEEL)
	_rect(img, 11, 4, 1, 11, STEEL_L)
	_tri_up(img, 12, 4, 1, 2, STEEL_L)
	_glow(img, 12, 9, 4.0, CYAN, 0.30)
	_rect(img, 7, 15, 10, 2, GOLD_D)
	_rect(img, 7, 15, 10, 1, GOLD)
	_px(img, 6, 15, GOLD); _px(img, 17, 15, GOLD)
	_rect(img, 11, 17, 2, 4, Color(0.40, 0.27, 0.18))
	_disc_o(img, 12, 21, 1.6, GOLD, GOLD_D)
	_px(img, 12, 20, GOLD_L)
	return img

func _gen_armor() -> Image:
	var img := _new(false)
	_trapezoid(img, 12, 3, 12, 7.0, 8.0, STEEL_D)
	_trapezoid(img, 12, 4, 12, 6.0, 7.0, STEEL)
	for y in range(12, 22):
		var w := int(round(8.0 * (1.0 - float(y - 12) / 9.5)))
		_rect(img, 12 - w, y, 1, 1, STEEL_D)
		_rect(img, 12 + w, y, 1, 1, STEEL_D)
		if w > 1:
			_rect(img, 12 - w + 1, y, (w - 1) * 2, 1, STEEL)
	_rect(img, 8, 5, 2, 8, STEEL_L)
	_glow(img, 12, 10, 3.0, ARCANE, 0.5)
	_disc_o(img, 12, 10, 2.4, ARCANE, INK_SOFT)
	_disc(img, 12, 10, 1.3, ARCANE_L)
	for ry in [5, 9, 13]:
		_px(img, 6, ry, STEEL_L)
		_px(img, 18, ry, STEEL_L)
	return img

func _gen_relic() -> Image:
	var img := _new(false)
	_disc_o(img, 12, 15, 6.0, GOLD, GOLD_D)
	_disc(img, 12, 15, 3.0, Color(0, 0, 0, 0))
	_px(img, 9, 12, GOLD_L)
	_glow(img, 12, 6, 3.4, CYAN, 0.7)
	_disc_o(img, 12, 6, 3.0, CYAN, INK_SOFT)
	_disc(img, 12, 6, 1.7, CYAN_L)
	_px(img, 11, 5, Color(1, 1, 1))
	_px(img, 12, 2, CYAN_L); _px(img, 8, 6, CYAN_L); _px(img, 16, 6, CYAN_L)
	return img

func _gen_artifact() -> Image:
	var img := _new(false)
	_glow(img, 12, 12, 9.0, ARCANE, 0.45)
	_disc(img, 12, 12, 8.0, Color(ARCANE.r, ARCANE.g, ARCANE.b, 0.28))
	_disc(img, 12, 12, 5.0, Color(ARCANE.r, ARCANE.g, ARCANE.b, 0.30))
	for i in range(10):
		var w := int(round(3.5 * (1.0 - float(i) / 10.0)))
		_rect(img, 12 - w, 12 - i, w * 2 + 1, 1, ARCANE)
		_rect(img, 12 - w, 12 + i, w * 2 + 1, 1, ARCANE)
		_rect(img, 12 - i, 12 - w, 1, w * 2 + 1, ARCANE)
		_rect(img, 12 + i, 12 - w, 1, w * 2 + 1, ARCANE)
	_disc(img, 12, 12, 2.4, ARCANE_L)
	_disc(img, 12, 12, 1.1, Color(1, 1, 1))
	return img

func _gen_potion() -> Image:
	var img := _new(false)
	_rect(img, 10, 3, 4, 2, Color(0.40, 0.28, 0.18))
	_rect(img, 10, 5, 4, 3, STEEL_D)
	_disc_o(img, 12, 15, 6.0, INK_SOFT, INK)
	_disc(img, 12, 15, 5.2, Color(0.55, 0.78, 0.88))
	_glow(img, 12, 16, 4.4, BLOOD, 0.45)
	_ellipse(img, 12, 17, 4.4, 3.6, BLOOD)
	_ellipse(img, 12, 17, 3.4, 2.6, BLOOD.lightened(0.14))
	_rect(img, 9, 12, 1, 6, Color(1, 1, 1, 0.7))
	_px(img, 14, 11, Color(1, 1, 1, 0.6))
	return img

# --- Icônes de nœud de carte (palette "Les Strates", fond transparent) ---------
func _gen_node_combat() -> Image:
	var img := _new(false)
	_line(img, 5, 19, 18, 5, INK); _line(img, 6, 19, 19, 5, INK)
	_line(img, 5, 18, 17, 5, STEEL); _line(img, 6, 18, 18, 5, STEEL_L)
	_px(img, 19, 4, STEEL_L)
	_line(img, 19, 19, 6, 5, INK); _line(img, 18, 19, 5, 5, INK)
	_line(img, 19, 18, 7, 5, STEEL); _line(img, 18, 18, 6, 5, STEEL_L)
	_px(img, 4, 4, STEEL_L)
	_line(img, 3, 17, 8, 20, GOLD); _line(img, 21, 17, 16, 20, GOLD)
	_disc_o(img, 5, 20, 1.4, GOLD, GOLD_D)
	_disc_o(img, 19, 20, 1.4, GOLD, GOLD_D)
	_glow(img, 12, 12, 2.4, CYAN_L, 0.7)
	_px(img, 12, 12, Color(1, 1, 1)); _px(img, 12, 11, CYAN_L); _px(img, 13, 12, CYAN_L)
	return img

func _gen_node_boss() -> Image:
	var img := _new(false)
	_line(img, 5, 14, 3, 7, BONE_D); _line(img, 6, 14, 4, 7, BONE)
	_px(img, 3, 6, BONE); _px(img, 4, 5, BONE)
	_line(img, 19, 14, 21, 7, BONE_D); _line(img, 18, 14, 20, 7, BONE)
	_px(img, 21, 6, BONE); _px(img, 20, 5, BONE)
	_rect(img, 6, 14, 13, 5, GOLD_D)
	_rect(img, 6, 14, 13, 1, GOLD_L)
	_rect(img, 7, 15, 11, 3, GOLD)
	_tri_up(img, 8, 14, 2, 4, GOLD); _tri_up(img, 12, 14, 2, 6, GOLD); _tri_up(img, 16, 14, 2, 4, GOLD)
	_px(img, 8, 10, GOLD_L); _px(img, 16, 10, GOLD_L)
	_glow(img, 12, 8, 2.6, EMBER, 0.75)
	_diamond(img, 12, 8, 2, EMBER.darkened(0.2))
	_diamond(img, 12, 8, 1, EMBER)
	_px(img, 12, 7, GOLD_L)
	_diamond(img, 12, 16, 1, EMBER); _px(img, 12, 16, GOLD_L)
	return img

func _gen_node_elite() -> Image:
	var img := _new(false)
	_tri_up(img, 6, 7, 1, 4, BONE_D); _tri_up(img, 18, 7, 1, 4, BONE_D)
	_px(img, 6, 3, BONE); _px(img, 18, 3, BONE)
	_disc_o(img, 12, 10, 6.0, BONE_D, INK)
	_disc(img, 12, 9, 5.2, BONE)
	_ellipse(img, 9, 6, 1.6, 1.3, Color(1, 1, 0.95))
	_rect(img, 8, 8, 3, 3, INK); _rect(img, 14, 8, 3, 3, INK)
	_glow(img, 9.5, 9.5, 1.8, EMBER, 0.7); _glow(img, 15.5, 9.5, 1.8, EMBER, 0.7)
	_px(img, 9, 9, EMBER); _px(img, 15, 9, EMBER)
	_px(img, 9, 8, GOLD_L); _px(img, 15, 8, GOLD_L)
	_px(img, 12, 12, INK)
	_rect(img, 8, 15, 9, 3, BONE_D); _rect(img, 8, 15, 9, 1, BONE)
	for tx in range(9, 17, 2):
		_rect(img, tx, 15, 1, 3, INK)
	return img

func _gen_node_shop() -> Image:
	var img := _new(false)
	var leather := Color(0.45, 0.32, 0.22)
	var leather_d := leather.darkened(0.35)
	_glow(img, 12, 6, 2.4, GOLD, 0.55)
	_disc_o(img, 12, 6, 2.3, GOLD, GOLD_D); _px(img, 11, 5, GOLD_L)
	_disc_o(img, 12, 15, 7.0, leather_d, INK)
	_disc(img, 12, 15, 6.0, leather)
	_ellipse(img, 9, 12, 2.3, 1.6, leather.lightened(0.22))
	_rect(img, 8, 8, 8, 2, leather_d)
	_rect(img, 7, 10, 10, 1, GOLD_D); _rect(img, 7, 9, 10, 1, GOLD)
	_diamond(img, 12, 16, 2, GOLD); _px(img, 12, 16, GOLD_L)
	return img

func _gen_node_event() -> Image:
	var img := _new(false)
	_glow(img, 12, 12, 8.5, ARCANE, 0.45)
	_disc(img, 12, 12, 8.0, Color(ARCANE.r, ARCANE.g, ARCANE.b, 0.25))
	_diamond(img, 12, 12, 7, ARCANE.darkened(0.35))
	_diamond(img, 12, 12, 6, ARCANE)
	_diamond(img, 12, 12, 4, ARCANE.darkened(0.45))
	_rect(img, 10, 8, 4, 1, CYAN_L)
	_px(img, 13, 9, CYAN_L); _px(img, 13, 10, CYAN_L)
	_px(img, 12, 11, CYAN_L); _px(img, 12, 12, CYAN_L)
	_px(img, 12, 13, CYAN_L)
	_glow(img, 12, 15, 1.4, Color(1, 1, 1), 0.8); _px(img, 12, 15, Color(1, 1, 1))
	return img

func _gen_node_rest() -> Image:
	var img := _new(false)
	var wood := Color(0.45, 0.32, 0.21)
	var wood_l := Color(0.55, 0.40, 0.27)
	_line(img, 5, 19, 16, 15, INK); _line(img, 19, 19, 8, 15, INK)
	_line(img, 5, 18, 16, 14, wood); _line(img, 6, 18, 17, 14, wood_l)
	_line(img, 19, 18, 8, 14, wood); _line(img, 18, 18, 7, 14, wood_l)
	_px(img, 5, 18, wood_l); _px(img, 19, 18, wood_l)
	_glow(img, 12, 12, 5.0, EMBER, 0.55)
	_tri_up(img, 12, 15, 4, 10, EMBER.darkened(0.25))
	_tri_up(img, 12, 15, 3, 8, EMBER)
	_tri_up(img, 12, 14, 2, 6, GOLD)
	_px(img, 12, 8, GOLD_L)
	_px(img, 10, 13, EMBER.lightened(0.1)); _px(img, 14, 13, EMBER)
	_px(img, 9, 18, EMBER); _px(img, 15, 18, GOLD)
	return img

# --- Terrain par biome --------------------------------------------------------
func _gen_ground(a: Color, b: Color) -> Image:
	var img := _new(true)
	img.fill(a)
	var joint_outer := a.darkened(0.42).lerp(INK, 0.55)
	var joint_inner := a.darkened(0.22).lerp(INK_SOFT, 0.35)
	for i in TILE:
		_px(img, i, 0, joint_outer);  _px(img, 0, i, joint_outer)
		_px(img, i, 12, joint_inner); _px(img, 12, i, joint_inner)
	for i in TILE:
		_px(img, i, 1,  a.lightened(0.10)); _px(img, 1,  i, a.lightened(0.10))
		_px(img, i, 13, a.lightened(0.06)); _px(img, 13, i, a.lightened(0.06))
	for i in TILE:
		_px(img, i, 11, a.darkened(0.16)); _px(img, 11, i, a.darkened(0.16))
	# Grain tramé (Bayer) : transitions douces sans bruit criard.
	for y in TILE:
		for x in TILE:
			var thr := (BAYER4[y & 3][x & 3] + 0.5) / 16.0
			var r := rng.randf()
			if r > 0.90 and 0.5 > thr:
				_px(img, x, y, b)
			elif r < 0.06:
				_px(img, x, y, a.darkened(0.22))
			elif (x * 5 + y * 3) % 17 == 0:
				_px(img, x, y, a.lightened(0.06))
	for p in [Vector2i(2, 2), Vector2i(14, 2), Vector2i(2, 14), Vector2i(14, 14)]:
		_px(img, p.x, p.y, b.lightened(0.14))
	for i in range(7):
		_px(img, i, 0, a.lightened(0.09)); _px(img, 0, i, a.lightened(0.07))
	var edge := a.darkened(0.40).lerp(INK_SOFT, 0.5)
	for i in TILE:
		_px(img, i, TILE - 1, edge)
		_px(img, TILE - 1, i, edge)
	return img

func _gen_tree(trunk: Color, leaf: Color, style: String) -> Image:
	var img := _new(false)
	match style:
		"round":
			_rect(img, 11, 15, 2, 7, trunk.darkened(0.2))
			_rect(img, 11, 15, 1, 7, trunk)
			_disc_o(img, 12, 10, 7.0, leaf.darkened(0.40), INK_SOFT)
			_disc(img, 12, 10, 6.0, leaf)
			_disc(img, 9, 7, 2.4, leaf.lightened(0.28))
			_px(img, 8, 6, leaf.lightened(0.45))
		"pine":
			_rect(img, 11, 18, 2, 4, trunk)
			_tri_up(img, 12, 19, 7, 8, leaf.darkened(0.40))
			_tri_up(img, 12, 19, 6, 7, leaf)
			_tri_up(img, 12, 14, 5, 6, leaf.darkened(0.16))
			_tri_up(img, 12, 10, 4, 5, leaf.lightened(0.18))
		"cactus":
			_rect(img, 10, 5, 4, 17, leaf.darkened(0.32))
			_rect(img, 11, 5, 3, 17, leaf)
			_rect(img, 11, 5, 1, 17, leaf.lightened(0.22))
			_rect(img, 6, 9, 2, 6, leaf); _rect(img, 6, 13, 3, 2, leaf)
			_rect(img, 16, 11, 2, 6, leaf); _rect(img, 15, 15, 3, 2, leaf)
			for yy in range(7, 21, 3):
				_px(img, 12, yy, leaf.lightened(0.38))
		"dead":
			_rect(img, 11, 5, 2, 17, trunk.darkened(0.2))
			_rect(img, 11, 5, 1, 17, trunk)
			_rect(img, 7, 11, 5, 1, trunk); _rect(img, 7, 8, 1, 4, trunk)
			_rect(img, 13, 13, 5, 1, trunk); _rect(img, 17, 9, 1, 5, trunk)
			_rect(img, 10, 4, 4, 2, trunk)
		_:
			_disc_o(img, 12, 12, 6.0, leaf.darkened(0.3), INK_SOFT)
			_disc(img, 12, 12, 5.0, leaf)
	return img

func _gen_rock(c: Color) -> Image:
	var img := _new(false)
	_ellipse(img, 12, 15, 8.5, 6.5, INK_SOFT)
	_ellipse(img, 12, 15, 7.5, 5.5, c)
	_ellipse(img, 9, 12, 2.8, 2.0, c.lightened(0.32))
	_rect(img, 13, 11, 1, 8, c.darkened(0.42))
	_rect(img, 13, 14, 4, 1, c.darkened(0.42))
	_rect(img, 6, 18, 11, 1, c.darkened(0.32))
	return img

func _gen_water(c: Color) -> Image:
	var img := _new(true)
	var base := c.darkened(0.45)
	img.fill(base)
	var trough := c.darkened(0.32)
	var mid    := c.lightened(0.06)
	var crest  := c.lightened(0.40)
	for y in range(1, TILE, 4):
		var off := (y / 4) % 3
		for x in TILE:
			var phase := (x + off * 5) % 12
			var ty := y + (phase / 6)
			if ty < TILE: _px(img, x, ty, trough)
			var my := y + 1 + (phase / 8)
			if my < TILE: _px(img, x, my, mid)
			if phase == 0 or phase == 6:
				var cy := y + 1
				if cy < TILE: _px(img, x, cy, crest)
				if cy - 1 >= 0: _px(img, x, cy - 1, Color(1.0, 1.0, 1.0, 0.55))
	for y in TILE:
		for x in TILE:
			if (x * 3 + y * 7) % 23 == 0:
				_px(img, x, y, crest.lightened(0.18))
	for i in TILE:
		_px(img, i, TILE - 1, base.darkened(0.35))
		_px(img, TILE - 1, i, base.darkened(0.35))
	_px(img, TILE - 1, TILE - 1, base.darkened(0.50))
	return img

func _gen_decor(c: Color, style: String) -> Image:
	var img := _new(false)
	match style:
		"flower":
			_rect(img, 12, 14, 1, 6, POISON.darkened(0.2))
			_glow(img, 12, 12, 2.2, c, 0.45)
			_disc_o(img, 12, 12, 2.4, c, INK_SOFT)
			_px(img, 12, 12, GOLD_L)
		"mushroom":
			_rect(img, 12, 16, 2, 4, BONE)
			_glow(img, 13, 13, 3.0, c, 0.35)
			_ellipse(img, 13, 14, 4.2, 2.8, c.darkened(0.25))
			_ellipse(img, 13, 13, 3.4, 2.0, c)
			_px(img, 11, 13, Color(1, 1, 1)); _px(img, 14, 14, Color(1, 1, 1))
		"bones":
			_rect(img, 8, 16, 8, 1, BONE)
			_rect(img, 8, 15, 1, 3, BONE); _rect(img, 15, 15, 1, 3, BONE)
			_px(img, 7, 15, BONE_D); _px(img, 16, 15, BONE_D)
		"crystal":
			_glow(img, 12, 13, 4.0, c, 0.6)
			_diamond(img, 12, 14, 4, c.darkened(0.3))
			_diamond(img, 12, 14, 3, c)
			_rect(img, 12, 11, 1, 6, c.lightened(0.48))
			_px(img, 11, 12, Color(1, 1, 1))
		"reed":
			for sx in [9, 12, 15]:
				_rect(img, sx, 11, 1, 9, c.darkened(0.15))
				_ellipse(img, sx, 10, 1.4, 2.4, c.darkened(0.3))
		"ember":
			_glow(img, 12, 16, 4.0, EMBER, 0.6)
			_ellipse(img, 12, 17, 3.4, 2.0, INK_SOFT)
			_ellipse(img, 12, 16, 2.4, 1.6, EMBER.darkened(0.2))
			_ellipse(img, 12, 16, 1.4, 1.0, EMBER)
			_px(img, 12, 14, GOLD_L)
		_:
			_disc_o(img, 12, 14, 2.0, c, INK_SOFT)
	return img

func _gen_road() -> Image:
	var img := _new(true)
	var dirt := Color(0.24, 0.20, 0.18)
	img.fill(dirt)
	for i in 60:
		var x := rng.randi_range(0, TILE - 1)
		var y := rng.randi_range(0, TILE - 1)
		_px(img, x, y, dirt.darkened(rng.randf() * 0.35))
	for i in 7:
		var x := rng.randi_range(2, TILE - 3)
		var y := rng.randi_range(2, TILE - 3)
		_ellipse(img, x, y, 1.4, 1.1, Color(0.40, 0.36, 0.33))
		_px(img, x - 1, y - 1, Color(0.50, 0.46, 0.42))
	return img
