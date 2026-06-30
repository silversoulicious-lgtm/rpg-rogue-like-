extends SceneTree
# Générateur d'assets pixel-art — IDENTITÉ VISUELLE "Les Strates".
# Refonte façon Moonring : palette restreinte med-fantasy NÉON, silhouettes
# lisibles, contour quasi-noir cohérent, lumière en haut-gauche, halos néon
# (glow/bloom) sur les éléments magiques et dithering rétro (Bayer) sur les sols.
# Lancé en headless : godot --headless --script res://_assets_gen.gd
# Produit des PNG 32x32 dans res://assets/.
#
# NOTE : ce script et le moteur de rendu hors-ligne (outils de dev) partagent la
# même logique ; les PNG livrés dans assets/ doivent rester cohérents avec lui.

const TILE := 32
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

	# --- Nouveaux monstres (Pass 1) + Boss (Pass 2) ---
	for k in ["araignee", "sanglier", "chauvesouris", "serpent", "ours",
			"zombie", "dullahan", "liche", "banshee", "revenant",
			"brigand", "gnoll", "troll", "kobold", "cultiste",
			"elementaire_feu", "golem", "fee", "drake", "coffre", "mimic",
			"roi_liche", "seigneur_fantome", "wyrm", "araignee_mere", "troll_ancestral",
			"paladin_dechu", "sorciere", "bourreau", "oeil_neant", "dieu_bete", "ame", "chaudron"]:
		_save(_gen_creature(k), k)

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
	var DataClass = load("res://scripts/Data.gd")
	for b in DataClass.BIOMES:
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
	_ellipse(img, 16, 28, 8.7, 2.4, Color(INK.r, INK.g, INK.b, 0.34))

# Triangle rempli d'un dégradé 3 bandes gauche(lumière)->droite(ombre).
func _tri_band(img: Image, cx: int, base_y: int, half_w: int, height: int, c_light: Color, c_mid: Color, c_dark: Color) -> void:
	for i in range(height):
		var w := int(round(half_w * (1.0 - float(i) / float(height))))
		var yy := base_y - i
		var span: float = max(1, 2 * w)
		for xx in range(cx - w, cx + w + 1):
			var t: float = (xx - (cx - w)) / span
			var c: Color = c_light if t < 0.35 else (c_mid if t < 0.7 else c_dark)
			_px(img, xx, yy, c)

# Disque rempli d'un dégradé 3 bandes gauche(lumière)->droite(ombre).
func _disc_band(img: Image, cx: int, cy: int, r: float, c_light: Color, c_mid: Color, c_dark: Color) -> void:
	for yy in range(int(cy - r), int(cy + r) + 1):
		for xx in range(int(cx - r), int(cx + r) + 1):
			var dx := (xx - cx) / r
			var dy := (yy - cy) / r
			if dx * dx + dy * dy <= 1.0:
				var t: float = (xx - (cx - r)) / (2.0 * r)
				var c: Color = c_light if t < 0.35 else (c_mid if t < 0.7 else c_dark)
				_px(img, xx, yy, c)

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
		_px(img, i, 16, INK_SOFT.darkened(0.1))
		_px(img, 16, i, INK_SOFT.darkened(0.1))
	_px(img, 3, 3, FLOOR_B.lightened(0.12))
	_px(img, 19, 3, FLOOR_B.lightened(0.12))
	return img

func _gen_wall() -> Image:
	var img := _new(true)
	img.fill(STONE)
	var brick_h := 8
	var brick_w := 11
	var row := 0
	for by in range(0, TILE, brick_h):
		for x in TILE:
			_px(img, x, by, INK)
			_px(img, x, by + 1, INK.lerp(STONE_D, 0.4))
			if by + 2 < TILE:
				_px(img, x, by + 2, STONE_L)
		var off := (brick_w / 2) if (row % 2 == 1) else 0
		var bx := -off
		while bx <= TILE:
			for yy in range(by + 2, by + brick_h):
				_px(img, bx, yy, INK)
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
	var crystal_pos := [Vector2i(7, 5), Vector2i(23, 13), Vector2i(4, 21), Vector2i(25, 4)]
	for cp in crystal_pos:
		_glow(img, cp.x, cp.y, 3.2, ARCANE, 0.55)
		_px(img, cp.x, cp.y, ARCANE)
		_px(img, cp.x, cp.y - 1, ARCANE_L)
		_px(img, cp.x - 1, cp.y, ARCANE.darkened(0.3))
	return img

func _gen_stairs() -> Image:
	var img := _new(false)                        # transparent : posé sur le sol
	_disc_o(img, 16, 17, 12.0, INK_SOFT, INK)      # masse de l'arche
	_glow(img, 16.0, 18.7, 12.0, ARCANE, 0.55)
	_ellipse(img, 16, 19, 8.7, 10.0, Color(ARCANE.r, ARCANE.g, ARCANE.b, 0.55))
	_ellipse(img, 16, 20, 6.0, 7.3, Color(ARCANE_L.r, ARCANE_L.g, ARCANE_L.b, 0.6))
	for s in range(3):
		var y := 19 - s * 3
		var w := 5 - s
		_rect(img, 12 - w, y, w * 2, 1, Color(CYAN_L.r, CYAN_L.g, CYAN_L.b, 0.75))
	_glow(img, 16.0, 13.3, 5.3, GOLD_L, 0.7)
	_tri_up(img, 16, 12, 5, 5, GOLD_L)
	_tri_up(img, 16, 15, 5, 4, GOLD)
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
		"araignee": _fig_araignee(img)
		"sanglier": _fig_sanglier(img)
		"chauvesouris": _fig_chauvesouris(img)
		"serpent": _fig_serpent(img)
		"ours":    _fig_ours(img)
		"zombie":  _fig_zombie(img)
		"dullahan": _fig_dullahan(img)
		"liche":   _fig_liche(img)
		"banshee": _fig_banshee(img)
		"revenant": _fig_revenant(img)
		"brigand": _fig_brigand(img)
		"gnoll":   _fig_gnoll(img)
		"troll":   _fig_troll(img)
		"kobold":  _fig_kobold(img)
		"cultiste": _fig_cultiste(img)
		"elementaire_feu": _fig_elementaire_feu(img)
		"golem":   _fig_golem(img)
		"fee":     _fig_fee(img)
		"drake":   _fig_drake(img)
		"coffre":  _fig_coffre(img)
		"mimic":   _fig_mimic(img)
		"roi_liche": _fig_roi_liche(img)
		"seigneur_fantome": _fig_seigneur_fantome(img)
		"wyrm":    _fig_wyrm(img)
		"araignee_mere": _fig_araignee_mere(img)
		"troll_ancestral": _fig_troll_ancestral(img)
		"paladin_dechu": _fig_paladin_dechu(img)
		"sorciere": _fig_sorciere(img)
		"bourreau": _fig_bourreau(img)
		"oeil_neant": _fig_oeil_neant(img)
		"dieu_bete": _fig_dieu_bete(img)
		"ame":     _fig_ame(img)
		"chaudron": _fig_chaudron(img)
		_:         _fig_knight(img)
	return img

# Reflet d'œil lumineux générique, avec halo néon.
func _glow_eyes(img: Image, cx: int, ey: int, c: Color, spread: int = 3) -> void:
	_glow(img, cx - spread + 0.5, ey + 0.5, 2.7, c, 0.7)
	_glow(img, cx + spread - 0.5, ey + 0.5, 2.7, c, 0.7)
	_rect(img, cx - spread, ey, 3, 3, c)
	_rect(img, cx + spread - 1, ey, 3, 3, c)
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
	_trapezoid(img, 16, 15, 28, 4.8, 8.0, ARCANE.darkened(0.4))
	_rect(img, 12, 24, 4, 5, STEEL_D); _rect(img, 12, 24, 4, 1, STEEL)
	_rect(img, 17, 24, 4, 5, STEEL_D); _rect(img, 17, 24, 4, 1, STEEL)
	_trapezoid_o(img, 16, 20, 27, 3.5, 5.3, ARCANE.darkened(0.25))
	_rect(img, 16, 21, 1, 5, ARCANE_L.darkened(0.1))
	_trapezoid_o(img, 16, 13, 21, 4.3, 4.8, STEEL_D)
	_trapezoid(img, 16, 15, 20, 3.2, 3.7, STEEL_L)
	_rect(img, 13, 15, 7, 1, CYAN)
	_glow(img, 16.0, 17.3, 3.5, CYAN, 0.6)
	_diamond(img, 16, 17, 3, CYAN); _px(img, 16, 17, Color(1, 1, 1))
	_disc_o(img, 11, 15, 2.3, STEEL, STEEL_D); _disc_o(img, 21, 15, 2.3, STEEL, STEEL_D)
	_rect(img, 9, 16, 3, 5, ARCANE.darkened(0.1))
	_rect(img, 20, 16, 3, 5, ARCANE.darkened(0.1))
	_px(img, 9, 20, SKIN); _px(img, 21, 20, SKIN)
	_disc_o(img, 16, 9, 4.9, ROSE_D, INK)
	_ellipse(img, 16, 11, 3.3, 3.6, SKIN)
	_rect(img, 12, 9, 3, 5, ROSE); _rect(img, 19, 9, 3, 5, ROSE)
	_px(img, 12, 9, ROSE_L)
	_rect(img, 12, 7, 9, 3, ROSE); _px(img, 13, 7, ROSE_L)
	_rect(img, 13, 9, 7, 1, ROSE_D)
	_px(img, 15, 12, INK); _px(img, 19, 12, INK)
	_px(img, 15, 11, SKIN_D); _px(img, 19, 11, SKIN_D)
	_px(img, 16, 15, SKIN_D)
	_rect(img, 13, 8, 7, 1, GOLD); _glow(img, 16.0, 8.0, 2.1, CYAN_L, 0.7); _px(img, 16, 8, CYAN_L)

# --- Vue de DOS (déplacement vers le haut) ---
func _fig_aria_back(img: Image) -> void:
	_ground_shadow(img)
	_rect(img, 12, 24, 4, 5, STEEL_D); _rect(img, 17, 24, 4, 5, STEEL_D)
	_trapezoid_o(img, 16, 12, 29, 4.8, 10.0, ARCANE.darkened(0.45))
	_trapezoid(img, 16, 13, 28, 3.7, 8.0, ARCANE)
	_rect(img, 16, 13, 1, 15, ARCANE_L.darkened(0.12))
	_px(img, 12, 17, ARCANE_L.darkened(0.2)); _px(img, 20, 21, ARCANE_L.darkened(0.2))
	_disc_o(img, 11, 15, 2.3, STEEL, STEEL_D); _disc_o(img, 21, 15, 2.3, STEEL, STEEL_D)
	_rect(img, 12, 13, 8, 1, CYAN)
	_disc_o(img, 16, 9, 4.9, ROSE_D, INK)
	_disc(img, 16, 9, 4.1, ROSE)
	_ellipse(img, 13, 7, 1.9, 1.6, ROSE_L)
	_rect(img, 15, 12, 3, 11, ROSE_D); _rect(img, 15, 12, 3, 9, ROSE)
	_px(img, 15, 16, ROSE_L); _px(img, 16, 20, ROSE_D)
	_rect(img, 12, 8, 8, 1, GOLD)

# --- Vue de PROFIL (orientée vers la DROITE, miroir à gauche) ---
func _fig_aria_side(img: Image) -> void:
	_ground_shadow(img)
	_trapezoid(img, 12, 15, 28, 3.2, 6.9, ARCANE.darkened(0.45))
	_trapezoid(img, 12, 16, 27, 2.3, 5.3, ARCANE.darkened(0.2))
	_px(img, 7, 27, ARCANE.darkened(0.3))
	_rect(img, 15, 24, 4, 5, STEEL_D); _rect(img, 15, 24, 4, 1, STEEL)
	_rect(img, 17, 25, 4, 4, STEEL_D.darkened(0.08))
	_trapezoid_o(img, 16, 13, 23, 3.2, 4.0, STEEL_D)
	_trapezoid(img, 16, 15, 21, 2.3, 2.9, STEEL_L)
	_rect(img, 17, 16, 4, 1, CYAN)
	_disc_o(img, 15, 15, 2.3, STEEL, STEEL_D)
	_rect(img, 19, 16, 3, 5, ARCANE.darkened(0.1))
	_px(img, 20, 20, SKIN)
	_trapezoid_o(img, 12, 12, 25, 1.6, 2.4, ROSE_D)
	_trapezoid(img, 12, 12, 24, 0.9, 1.6, ROSE)
	_px(img, 12, 17, ROSE_L); _px(img, 12, 23, ROSE_D)
	_disc_o(img, 16, 9, 4.8, ROSE_D, INK)
	_disc(img, 15, 8, 4.0, ROSE)
	_ellipse(img, 13, 7, 1.6, 1.3, ROSE_L)
	_ellipse(img, 19, 11, 2.8, 3.1, SKIN)
	_px(img, 21, 11, SKIN_D)
	_rect(img, 19, 11, 1, 3, INK)
	_px(img, 20, 15, SKIN_D)
	_px(img, 17, 7, ROSE); _px(img, 19, 8, ROSE)
	_px(img, 16, 7, GOLD); _px(img, 17, 8, GOLD); _glow(img, 18.7, 9.3, 1.9, CYAN_L, 0.7); _px(img, 19, 9, CYAN_L)

# Classe « chevalier » (legacy) : armure d'acier, écharpe rouge, visière cyan.
func _fig_knight(img: Image) -> void:
	_ground_shadow(img)
	_trapezoid_o(img, 16, 15, 28, 3.3, 8.0, STEEL_D)
	_trapezoid(img, 16, 16, 27, 2.0, 6.0, STEEL)
	_rect(img, 8, 16, 4, 3, BLOOD)
	_px(img, 7, 17, BLOOD_D)
	_px(img, 11, 15, BLOOD)
	_rect(img, 13, 17, 5, 7, STEEL_L)
	_px(img, 13, 17, STEEL)
	_rect(img, 15, 19, 1, 4, Color(1, 1, 1, 0.55))
	_disc_o(img, 16, 9, 5.6, STEEL_D, INK)
	_disc(img, 16, 8, 4.5, STEEL)
	_ellipse(img, 13, 7, 2.1, 1.9, STEEL_L)
	_glow(img, 16.0, 9.3, 4.5, CYAN, 0.4)
	_rect(img, 12, 9, 8, 1, CYAN_L)
	_px(img, 12, 9, CYAN)
	_tri_up(img, 16, 4, 1, 4, BLOOD)
	_rect(img, 23, 12, 1, 12, STEEL_L)
	_rect(img, 21, 21, 4, 1, GOLD)

func _fig_mage(img: Image) -> void:
	_ground_shadow(img)
	_trapezoid_o(img, 16, 15, 28, 2.7, 8.7, ARCANE.darkened(0.45))
	_trapezoid(img, 16, 16, 27, 1.6, 6.7, ARCANE)
	_rect(img, 15, 19, 3, 8, ARCANE_L.darkened(0.1))
	_disc_o(img, 16, 11, 4.5, ARCANE.darkened(0.4), INK)
	_disc(img, 16, 11, 3.5, Color(0.86, 0.78, 0.66))
	_glow_eyes(img, 16, 9, CYAN, 3)
	_trapezoid_o(img, 16, 1, 8, 0.7, 6.0, ARCANE.darkened(0.25))
	_glow(img, 16.0, 1.3, 2.7, GOLD_L, 0.8); _px(img, 16, 1, GOLD_L)
	_px(img, 12, 8, GOLD)
	_rect(img, 8, 11, 1, 16, GOLD_D)
	_glow(img, 8.0, 9.3, 4.0, CYAN, 0.7)
	_disc_o(img, 8, 9, 2.7, CYAN, INK)
	_px(img, 8, 8, CYAN_L)

func _fig_ranger(img: Image) -> void:
	_ground_shadow(img)
	_trapezoid_o(img, 16, 15, 28, 3.3, 8.0, POISON.darkened(0.5))
	_trapezoid(img, 16, 16, 27, 2.1, 6.1, POISON.darkened(0.25))
	_rect(img, 15, 19, 3, 7, POISON.darkened(0.1))
	_disc_o(img, 16, 9, 5.6, POISON.darkened(0.5), INK)
	_ellipse(img, 16, 8, 4.5, 4.8, POISON.darkened(0.3))
	_ellipse(img, 16, 11, 3.2, 2.7, Color(0.07, 0.07, 0.10))
	_glow_eyes(img, 16, 11, CYAN_L, 3)
	for i in range(11):
		var yy := 6 + i
		var dx := int(round(3.0 * sin(float(i) / 10.0 * PI)))
		_px(img, 18 - dx, yy, GOLD_D)
	_rect(img, 24, 8, 1, 15, Color(0.85, 0.85, 0.9, 0.8))

func _fig_gobelin(img: Image) -> void:
	_ground_shadow(img)
	var skin := POISON.darkened(0.15)
	_trapezoid_o(img, 16, 17, 28, 4.0, 7.3, skin.darkened(0.35))
	_trapezoid(img, 16, 19, 27, 2.7, 5.6, skin)
	_rect(img, 13, 20, 5, 4, Color(0.45, 0.32, 0.22))
	_disc_o(img, 16, 12, 5.3, skin.darkened(0.3), INK)
	_disc(img, 16, 12, 4.3, skin)
	_ellipse(img, 13, 9, 1.7, 1.5, skin.lightened(0.28))
	_tri_up(img, 8, 15, 3, 7, skin.darkened(0.1))
	_tri_up(img, 24, 15, 3, 7, skin.darkened(0.1))
	_glow_eyes(img, 16, 11, GOLD_L, 3)
	_rect(img, 13, 15, 5, 1, INK)
	_px(img, 15, 15, BONE)
	_rect(img, 24, 17, 1, 7, STEEL_L)

func _fig_wolf(img: Image) -> void:
	_ground_shadow(img)
	var fur := Color(0.40, 0.42, 0.50)
	var fur_d := fur.darkened(0.45)
	var fur_l := fur.lightened(0.26)
	var fur_belly := fur.lightened(0.12)

	# queue (derrière le corps), recourbée vers le haut
	_ellipse(img, 27, 18, 3.0, 1.6, fur_d); _ellipse(img, 29, 15, 1.8, 1.6, fur_d)
	_px(img, 30, 13, fur_l)

	# pattes arrière (sombres, derrière le torse) puis pattes avant (claires, devant)
	_rect(img, 20, 23, 3, 6, fur_d); _rect(img, 13, 23, 3, 6, fur_d)
	_rect(img, 20, 27, 3, 1, INK_SOFT); _rect(img, 13, 27, 3, 1, INK_SOFT)
	_rect(img, 11, 22, 3, 7, fur); _rect(img, 18, 22, 3, 7, fur)
	_rect(img, 11, 27, 3, 1, INK_SOFT); _rect(img, 18, 27, 3, 1, INK_SOFT)

	# torse : col distinct pour que la tête ne fusionne pas avec le corps
	_ellipse(img, 18, 19, 9.0, 5.4, fur_d)
	_ellipse(img, 18, 19, 7.8, 4.4, fur)
	_ellipse(img, 18, 22, 6.5, 2.4, fur_belly)
	_ellipse(img, 21, 15, 2.6, 2.2, fur_l)

	# tête, séparée du torse par un coin d'ombre + son propre contour
	_ellipse(img, 11, 17, 2.6, 2.0, fur_d)
	_disc_o(img, 7, 15, 4.4, fur_d, INK)
	_disc(img, 7, 15, 3.5, fur)
	_ellipse(img, 6, 14, 1.4, 1.1, fur_l)
	# museau, en saillie pour que la silhouette se lise comme une tête
	_trapezoid(img, 4, 15, 18, 1.8, 1.0, fur_d); _trapezoid(img, 4, 15, 17, 1.4, 0.8, fur)
	_px(img, 1, 17, INK)
	# oreilles
	_tri_up(img, 4, 12, 1, 4, fur_d); _tri_up(img, 9, 12, 1, 4, fur_d)
	_px(img, 4, 9, fur_l); _px(img, 9, 9, fur_l)

	_glow(img, 6.3, 14.7, 1.8, CYAN_L, 0.7)
	_px(img, 6, 14, CYAN_L)

func _fig_skeleton(img: Image) -> void:
	_ground_shadow(img)
	var bn := BONE
	var bn_d := BONE_D
	var bn_l := BONE.lightened(0.12)

	# jambes en os individuels avec genou visible, plutôt qu'un coin plein
	for lx in [13, 18]:
		_rect(img, lx, 21, 2, 4, bn_d); _disc(img, lx + 1, 25, 1.3, bn)
		_rect(img, lx, 26, 2, 3, bn_d)
		_rect(img, lx - 1, 28, 4, 1, INK_SOFT)

	# bassin
	_trapezoid_o(img, 16, 18, 22, 3.3, 4.3, bn_d)
	_trapezoid(img, 16, 19, 21, 2.4, 3.3, bn)

	# cage thoracique : barres courbes qui se resserrent vers le bas + sternum
	for i in range(5):
		var ry := 10 + i * 2
		var hw := 5 - i / 2
		_rect(img, 16 - hw, ry, hw * 2 + 1, 1, bn_d)
		_rect(img, 16 - hw + 1, ry, hw * 2 - 1, 1, bn)
	_rect(img, 16, 10, 1, 9, bn_d)

	# bras le long du corps, avec coudes
	for ax in [10, 22]:
		_rect(img, ax, 12, 1, 5, bn_d); _disc(img, ax, 17, 1.0, bn)
		_rect(img, ax, 18, 1, 4, bn_d)
		_px(img, ax, 22, INK_SOFT)

	# crâne avec mâchoire + dents + orbites profondes
	_disc_o(img, 16, 7, 5.0, bn_d, INK)
	_disc(img, 16, 6, 4.2, bn)
	_rect(img, 12, 9, 8, 2, bn_d)
	for tx in range(12, 20, 2):
		_px(img, tx, 9, bn_l)
	_rect(img, 12, 5, 3, 3, INK); _rect(img, 17, 5, 3, 3, INK)
	_glow(img, 13.5, 6.5, 2.0, CYAN, 0.7); _glow(img, 18.5, 6.5, 2.0, CYAN, 0.7)
	_px(img, 13, 6, CYAN_L); _px(img, 18, 6, CYAN_L)
	_px(img, 16, 4, bn_d)

func _fig_orc(img: Image) -> void:
	_ground_shadow(img)
	var skin := Color(0.30, 0.44, 0.30)
	var skin_l := skin.lightened(0.20)
	_trapezoid_o(img, 15, 13, 28, 6.7, 10.0, skin.darkened(0.45))
	_trapezoid(img, 15, 15, 27, 5.3, 8.0, skin)
	_rect(img, 8, 16, 13, 3, Color(0.36, 0.25, 0.18))
	_rect(img, 11, 20, 8, 4, skin_l)
	_disc_o(img, 15, 9, 6.1, skin.darkened(0.4), INK)
	_disc(img, 15, 9, 5.1, skin)
	_ellipse(img, 12, 7, 2.1, 1.7, skin_l)
	_rect(img, 9, 8, 12, 1, INK)
	_glow_eyes(img, 15, 9, BLOOD, 4)
	_tri_up(img, 12, 17, 1, 5, BONE)
	_tri_up(img, 17, 17, 1, 5, BONE)
	_rect(img, 12, 15, 7, 1, INK)
	_rect(img, 24, 7, 1, 20, Color(0.36, 0.25, 0.18))
	_rect(img, 19, 7, 7, 7, STEEL_D)
	_rect(img, 20, 8, 4, 4, STEEL)
	_rect(img, 20, 8, 4, 1, STEEL_L)
	_px(img, 19, 9, STEEL_L); _px(img, 19, 11, STEEL_L)

func _fig_spectre(img: Image) -> void:
	_glow(img, 16.0, 12.0, 8.7, ARCANE, 0.5)
	_disc_o(img, 16, 12, 6.7, ARCANE.darkened(0.35), INK_SOFT)
	_disc(img, 16, 12, 5.6, ARCANE.darkened(0.1))
	_trapezoid(img, 16, 15, 27, 4.7, 8.0, ARCANE.darkened(0.1))
	for x in range(8, 25):
		var cut := 27 - (x % 3)
		for y in range(cut, TILE):
			_px(img, x, y, Color(0, 0, 0, 0))
	_ellipse(img, 16, 12, 3.5, 2.9, Color(0.06, 0.05, 0.10))
	_glow_eyes(img, 16, 11, CYAN_L, 3)
	_px(img, 16, 15, CYAN)
	_fade(img, 0.82)

func _fig_boss(img: Image) -> void:
	_ellipse(img, 16, 29, 10.7, 2.7, Color(INK.r, INK.g, INK.b, 0.40))
	_trapezoid_o(img, 16, 12, 29, 6.0, 11.3, INK_SOFT)
	_trapezoid(img, 16, 13, 28, 4.8, 9.3, Color(0.22, 0.12, 0.16))
	_rect(img, 15, 17, 3, 11, BLOOD_D)
	_rect(img, 11, 17, 11, 4, Color(0.30, 0.16, 0.20))
	_glow(img, 16.0, 18.7, 3.5, GOLD, 0.65)
	_disc_o(img, 16, 19, 2.7, GOLD, GOLD_D)
	_px(img, 16, 17, GOLD_L)
	_disc_o(img, 16, 9, 6.1, INK_SOFT, INK)
	_disc(img, 16, 9, 5.1, Color(0.26, 0.16, 0.20))
	_tri_up(img, 8, 8, 3, 8, BONE_D)
	_tri_up(img, 24, 8, 3, 8, BONE_D)
	_px(img, 8, 0, BONE); _px(img, 24, 0, BONE)
	_glow_eyes(img, 16, 9, EMBER, 4)
	_px(img, 12, 9, GOLD_L); _px(img, 20, 9, GOLD_L)
	_rect(img, 13, 13, 7, 1, INK)

# --- Nouveaux monstres (Pass 1) ----------------------------------------------
func _fig_araignee(img: Image) -> void:
	_ground_shadow(img)
	var leg: Color = POISON.darkened(0.5)
	for ey in [13, 17, 21]:
		_line(img, 11, 19, 1, ey, leg); _line(img, 11, 20, 3, ey + 1, leg)
		_line(img, 21, 19, 31, ey, leg); _line(img, 21, 20, 29, ey + 1, leg)
	_disc_o(img, 16, 20, 6.7, POISON.darkened(0.45), INK)
	_disc(img, 16, 20, 5.3, POISON.darkened(0.12))
	_ellipse(img, 13, 17, 2.1, 1.6, POISON.lightened(0.22))
	_disc_o(img, 16, 12, 4.0, POISON.darkened(0.32), INK)
	_disc(img, 16, 12, 2.9, POISON.darkened(0.05))
	_glow_eyes(img, 16, 11, BLOOD, 3)

func _fig_sanglier(img: Image) -> void:
	_ground_shadow(img)
	var fur := Color(0.50, 0.40, 0.34)
	var fur_d := fur.darkened(0.42)
	var fur_l := fur.lightened(0.20)
	var hide_head := fur.darkened(0.18)

	# pattes (trapues, sombres, derrière la silhouette du corps)
	_rect(img, 11, 24, 3, 4, fur_d); _rect(img, 21, 24, 3, 4, fur_d)
	_rect(img, 11, 27, 3, 1, INK_SOFT); _rect(img, 21, 27, 3, 1, INK_SOFT)

	# corps en tonneau, distinct de la tête via un coin d'ombre au cou
	_ellipse(img, 18, 20, 10.0, 6.2, fur_d)
	_ellipse(img, 18, 20, 8.7, 5.1, fur)
	_ellipse(img, 18, 23, 6.5, 2.2, fur.darkened(0.12))

	# crinière hérissée : rangée de piquants le long de l'échine
	for sx in range(11, 23, 2):
		_tri_up(img, sx, 15, 1, 3, fur_d)
	for sx in range(12, 22, 2):
		_tri_up(img, sx, 14, 1, 2, fur_l)

	# tête basse, avec son propre contour pour qu'elle se lise comme une masse distincte
	_ellipse(img, 10, 18, 2.4, 2.0, fur_d)
	_disc_o(img, 6, 18, 4.6, hide_head.darkened(0.3), INK)
	_disc(img, 6, 18, 3.7, hide_head)
	_ellipse(img, 5, 16, 1.3, 1.0, fur_l)
	# groin large et plat
	_rect(img, 0, 17, 5, 4, hide_head.lightened(0.10))
	_px(img, 0, 18, INK); _px(img, 0, 19, INK)
	# défenses recourbées
	_tri_up(img, 2, 22, 1, 4, BONE); _tri_up(img, 6, 22, 1, 3, BONE)
	_px(img, 1, 18, BONE_D)
	# petite oreille
	_tri_up(img, 8, 14, 2, 3, fur_d); _px(img, 8, 12, fur_l)

	_glow(img, 5.3, 16.7, 1.6, EMBER, 0.7)
	_px(img, 5, 16, EMBER)

func _fig_chauvesouris(img: Image) -> void:
	_ground_shadow(img)
	var body: Color = Color(0.45, 0.30, 0.42)
	_trapezoid(img, 5, 11, 20, 0.7, 5.3, body.darkened(0.4))
	_trapezoid(img, 27, 11, 20, 0.7, 5.3, body.darkened(0.4))
	_line(img, 9, 12, 4, 9, body.darkened(0.2)); _line(img, 23, 12, 28, 9, body.darkened(0.2))
	_disc_o(img, 16, 16, 4.0, body.darkened(0.3), INK); _disc(img, 16, 16, 3.1, body)
	_tri_up(img, 13, 12, 1, 4, body.darkened(0.2)); _tri_up(img, 19, 12, 1, 4, body.darkened(0.2))
	_glow_eyes(img, 16, 15, BLOOD, 1)
	_px(img, 15, 19, BONE); _px(img, 17, 19, BONE)

func _fig_serpent(img: Image) -> void:
	_ground_shadow(img)
	var sk: Color = Color(0.36, 0.62, 0.40)
	var sk_d: Color = sk.darkened(0.4)
	for i in range(14):
		var t: float = i / 13.0
		var x: int = int(9 + 9 * abs(sin(t * PI * 1.5)))
		var y: int = 27 - i
		_disc(img, x, y, 2.7, sk_d); _disc(img, x, y, 1.7, sk)
	_disc_o(img, 19, 9, 3.5, sk_d, INK); _disc(img, 19, 9, 2.5, sk)
	_glow_eyes(img, 19, 8, GOLD_L, 1)
	_line(img, 21, 11, 24, 12, BLOOD); _px(img, 24, 12, BLOOD); _px(img, 25, 11, BLOOD)

func _fig_ours(img: Image) -> void:
	_ground_shadow(img)
	var fur: Color = Color(0.46, 0.36, 0.31)
	var fur_d: Color = fur.darkened(0.42)
	_trapezoid_o(img, 16, 13, 28, 6.7, 9.3, fur_d)
	_trapezoid(img, 16, 15, 27, 5.3, 7.3, fur)
	_rect(img, 11, 20, 11, 4, fur.lightened(0.12))
	_disc_o(img, 16, 9, 5.9, fur_d, INK); _disc(img, 16, 9, 4.8, fur)
	_disc(img, 8, 5, 2.1, fur_d); _disc(img, 24, 5, 2.1, fur_d)
	_disc(img, 8, 5, 1.3, fur); _disc(img, 24, 5, 1.3, fur)
	_ellipse(img, 16, 12, 2.4, 1.7, fur.lightened(0.2)); _px(img, 16, 12, INK)
	_glow_eyes(img, 16, 8, EMBER, 3)
	_tri_up(img, 13, 21, 1, 4, BONE); _tri_up(img, 19, 21, 1, 4, BONE)

func _fig_zombie(img: Image) -> void:
	_ground_shadow(img)
	var sk: Color = Color(0.48, 0.62, 0.40)
	var sk_d: Color = sk.darkened(0.4)
	_glow(img, 16.0, 17.3, 8.0, POISON, 0.22)
	_trapezoid_o(img, 15, 15, 28, 3.7, 6.0, sk_d)
	_trapezoid(img, 15, 16, 27, 2.7, 4.7, sk)
	_rect(img, 12, 17, 7, 3, sk_d); _rect(img, 20, 16, 4, 3, sk); _rect(img, 24, 16, 3, 5, sk_d)
	_disc_o(img, 15, 9, 4.8, sk_d, INK); _disc(img, 15, 9, 3.9, sk)
	_ellipse(img, 12, 7, 1.6, 1.3, sk.lightened(0.2))
	_px(img, 13, 9, INK); _rect(img, 16, 9, 3, 1, INK)
	_glow(img, 13.3, 9.3, 1.6, POISON, 0.6); _rect(img, 13, 13, 4, 1, INK)

func _fig_dullahan(img: Image) -> void:
	_ground_shadow(img)
	_trapezoid_o(img, 16, 9, 28, 4.3, 8.0, STEEL_D)
	_trapezoid(img, 16, 11, 27, 3.2, 6.0, STEEL)
	_rect(img, 13, 12, 7, 7, STEEL_L); _rect(img, 15, 13, 1, 4, Color(1, 1, 1, 0.5))
	_disc_o(img, 11, 8, 2.3, STEEL, STEEL_D); _disc_o(img, 21, 8, 2.3, STEEL, STEEL_D)
	_px(img, 16, 8, BLOOD); _rect(img, 15, 8, 4, 1, BLOOD_D)
	_glow(img, 25.3, 18.7, 4.0, ARCANE, 0.4)
	_disc_o(img, 25, 19, 3.5, STEEL_D, INK); _disc(img, 25, 19, 2.5, BONE)
	_glow_eyes(img, 25, 17, EMBER, 1)
	_rect(img, 5, 12, 1, 13, STEEL_L)

func _fig_liche(img: Image) -> void:
	_ground_shadow(img)
	_trapezoid_o(img, 16, 15, 28, 2.7, 8.0, ARCANE.darkened(0.5))
	_trapezoid(img, 16, 16, 27, 1.6, 6.1, ARCANE.darkened(0.25))
	_rect(img, 15, 19, 3, 8, ARCANE_L.darkened(0.1))
	_disc_o(img, 16, 11, 4.5, BONE_D, INK); _disc(img, 16, 9, 3.6, BONE)
	_rect(img, 13, 9, 3, 3, INK); _rect(img, 17, 9, 3, 3, INK)
	_glow(img, 14.0, 10.0, 1.9, ARCANE_L, 0.7); _glow(img, 19.3, 10.0, 1.9, ARCANE_L, 0.7)
	_px(img, 13, 9, ARCANE_L); _px(img, 19, 9, ARCANE_L)
	_rect(img, 12, 5, 8, 1, GOLD)
	_tri_up(img, 12, 5, 1, 3, GOLD); _tri_up(img, 16, 5, 1, 3, GOLD); _tri_up(img, 20, 5, 1, 3, GOLD)
	_rect(img, 8, 9, 1, 17, GOLD_D)
	_glow(img, 8.0, 8.0, 3.5, ARCANE, 0.7); _disc_o(img, 8, 8, 2.4, ARCANE, INK); _px(img, 8, 7, ARCANE_L)

func _fig_banshee(img: Image) -> void:
	_glow(img, 16.0, 13.3, 9.3, CYAN, 0.35)
	_disc_o(img, 16, 11, 5.6, CYAN.darkened(0.4), INK_SOFT); _disc(img, 16, 11, 4.5, CYAN.darkened(0.12))
	for sx in [9, 12, 20, 23]:
		_line(img, sx, 11, sx + (3 if sx < 16 else -3), 24, CYAN.darkened(0.2))
	_trapezoid(img, 16, 15, 28, 4.7, 8.0, CYAN.darkened(0.18))
	for x in range(8, 25):
		var cut: int = 28 - (x % 3)
		for y in range(cut, TILE):
			_px(img, x, y, Color(0, 0, 0, 0))
	_ellipse(img, 16, 11, 3.2, 2.7, Color(0.05, 0.08, 0.10))
	_glow_eyes(img, 16, 9, Color(1, 1, 1), 3)
	_ellipse(img, 16, 15, 1.3, 2.1, Color(0.9, 1, 1, 0.8))
	_fade(img, 0.82)

func _fig_revenant(img: Image) -> void:
	_ground_shadow(img)
	var arm: Color = Color(0.30, 0.30, 0.38)
	_trapezoid_o(img, 16, 13, 28, 4.0, 7.3, arm.darkened(0.4))
	_trapezoid(img, 16, 15, 27, 2.9, 5.6, arm)
	_rect(img, 13, 17, 7, 4, arm.lightened(0.18))
	_disc_o(img, 16, 9, 5.1, arm.darkened(0.4), INK); _disc(img, 16, 9, 4.0, arm)
	_rect(img, 12, 9, 8, 1, INK)
	_glow_eyes(img, 16, 9, BLOOD, 3)
	_tri_up(img, 16, 4, 1, 4, BLOOD)
	_rect(img, 24, 11, 1, 15, STEEL_L); _rect(img, 7, 11, 1, 15, STEEL_L)

func _fig_brigand(img: Image) -> void:
	_ground_shadow(img)
	var cloth: Color = Color(0.40, 0.32, 0.26)
	_trapezoid_o(img, 16, 15, 28, 3.5, 7.3, cloth.darkened(0.4))
	_trapezoid(img, 16, 16, 27, 2.4, 5.6, cloth)
	_disc_o(img, 16, 9, 5.1, cloth.darkened(0.45), INK)
	_ellipse(img, 16, 11, 3.2, 2.7, Color(0.08, 0.07, 0.10))
	_glow_eyes(img, 16, 11, ARCANE_L, 1)
	_rect(img, 21, 17, 1, 7, STEEL_L); _rect(img, 20, 23, 4, 1, GOLD)
	_glow(img, 16.0, 16.0, 4.0, ARCANE, 0.18)

func _fig_gnoll(img: Image) -> void:
	_ground_shadow(img)
	var fur: Color = Color(0.68, 0.58, 0.34)
	var fur_d: Color = fur.darkened(0.4)
	_trapezoid_o(img, 16, 15, 28, 3.5, 6.7, fur_d)
	_trapezoid(img, 16, 16, 27, 2.4, 5.1, fur)
	_rect(img, 12, 19, 8, 3, Color(0.4, 0.3, 0.2))
	_disc_o(img, 16, 9, 4.8, fur_d, INK); _disc(img, 16, 9, 3.9, fur)
	_tri_up(img, 11, 7, 1, 4, fur_d); _tri_up(img, 21, 7, 1, 4, fur_d)
	_rect(img, 13, 11, 5, 3, fur.lightened(0.12))
	_px(img, 13, 12, INK); _px(img, 17, 12, INK); _px(img, 15, 12, BONE)
	_glow_eyes(img, 16, 9, GOLD_L, 1)
	_rect(img, 23, 13, 1, 11, STEEL_L)

func _fig_troll(img: Image) -> void:
	_ground_shadow(img)
	var sk: Color = Color(0.45, 0.60, 0.45)
	var sk_d: Color = sk.darkened(0.42)
	_trapezoid_o(img, 15, 12, 28, 7.3, 10.0, sk_d)
	_trapezoid(img, 15, 13, 27, 6.0, 8.0, sk)
	_rect(img, 9, 19, 12, 4, sk.lightened(0.12))
	for rp in [Vector2i(11, 21), Vector2i(17, 17), Vector2i(20, 24)]:
		_glow(img, rp.x, rp.y, 2.1, CYAN, 0.5); _px(img, rp.x, rp.y, CYAN_L)
	_disc_o(img, 15, 9, 5.6, sk_d, INK); _disc(img, 15, 9, 4.5, sk)
	_rect(img, 9, 11, 12, 1, INK)
	_glow_eyes(img, 15, 11, EMBER, 3)
	_tri_up(img, 12, 16, 1, 4, BONE); _tri_up(img, 17, 16, 1, 4, BONE)

func _fig_kobold(img: Image) -> void:
	_ground_shadow(img)
	var sk: Color = Color(0.80, 0.50, 0.35)
	var sk_d: Color = sk.darkened(0.4)
	_trapezoid_o(img, 16, 19, 28, 3.2, 5.1, sk_d)
	_trapezoid(img, 16, 20, 27, 2.1, 3.7, sk)
	_disc_o(img, 16, 13, 4.3, sk_d, INK); _disc(img, 16, 13, 3.3, sk)
	_rect(img, 15, 15, 5, 3, sk.lightened(0.1))
	_tri_up(img, 11, 12, 1, 5, sk_d); _tri_up(img, 21, 12, 1, 5, sk_d)
	_glow_eyes(img, 16, 12, GOLD_L, 1)
	_rect(img, 23, 16, 1, 7, STEEL_L); _tri_up(img, 17, 12, 1, 4, BONE)

func _fig_cultiste(img: Image) -> void:
	_ground_shadow(img)
	var robe: Color = Color(0.45, 0.25, 0.34)
	_trapezoid_o(img, 16, 11, 29, 2.7, 8.7, robe.darkened(0.45))
	_trapezoid(img, 16, 12, 28, 1.9, 6.9, robe)
	_disc_o(img, 16, 9, 4.5, robe.darkened(0.5), INK)
	_tri_up(img, 16, 8, 3, 5, robe.darkened(0.35))
	_ellipse(img, 16, 11, 2.7, 2.3, Color(0.06, 0.05, 0.08))
	_glow_eyes(img, 16, 11, BLOOD, 1)
	_glow(img, 16.0, 22.7, 4.3, BLOOD, 0.45)
	_diamond(img, 16, 23, 3, BLOOD.darkened(0.2)); _px(img, 16, 23, GOLD_L)

func _fig_elementaire_feu(img: Image) -> void:
	_glow(img, 16.0, 17.3, 12.0, EMBER, 0.5)
	_tri_up(img, 16, 28, 9, 21, EMBER.darkened(0.3))
	_tri_up(img, 16, 28, 7, 19, EMBER)
	_tri_up(img, 12, 25, 3, 9, EMBER.darkened(0.1)); _tri_up(img, 20, 25, 3, 9, EMBER.darkened(0.1))
	_tri_up(img, 16, 25, 4, 15, GOLD); _tri_up(img, 16, 21, 3, 9, GOLD_L)
	_glow_eyes(img, 16, 16, Color(1, 1, 1), 3); _px(img, 16, 7, GOLD_L)

func _fig_golem(img: Image) -> void:
	_ground_shadow(img)
	var st: Color = Color(0.58, 0.58, 0.64)
	var st_d: Color = st.darkened(0.4)
	var st_l: Color = st.lightened(0.16)
	_rect(img, 7, 12, 19, 17, INK)
	_rect(img, 8, 13, 16, 15, st_d); _rect(img, 9, 15, 13, 12, st); _rect(img, 9, 15, 13, 3, st_l)
	_rect(img, 11, 8, 11, 5, st_d); _rect(img, 12, 8, 8, 4, st)
	_rect(img, 4, 15, 3, 9, st_d); _rect(img, 25, 15, 3, 9, st_d)
	_glow(img, 13.3, 10.7, 1.9, ARCANE, 0.5); _glow(img, 18.7, 10.7, 1.9, ARCANE, 0.5)
	_px(img, 13, 11, ARCANE_L); _px(img, 19, 11, ARCANE_L)
	_line(img, 12, 17, 15, 23, st_d); _line(img, 19, 16, 17, 24, st_d)

func _fig_fee(img: Image) -> void:
	_glow(img, 16.0, 16.0, 9.3, ARCANE, 0.35)
	var skin := SKIN
	var dress := ARCANE
	var dress_d := ARCANE.darkened(0.30)

	# ailes : forme en goutte avec nervures plutôt que des blobs translucides plats
	for wing in [Vector2i(9, -1), Vector2i(23, 1)]:
		var wx: int = wing.x
		var sign: int = wing.y
		_ellipse(img, wx, 13, 3.0, 4.6, Color(ARCANE.r, ARCANE.g, ARCANE.b, 0.40))
		_ellipse(img, wx, 13, 1.8, 3.1, Color(ARCANE_L.r, ARCANE_L.g, ARCANE_L.b, 0.55))
		_line(img, 16 + sign, 13, wx, 9, Color(ARCANE_L.r, ARCANE_L.g, ARCANE_L.b, 0.6))
		_line(img, 16 + sign, 14, wx, 16, Color(ARCANE_L.r, ARCANE_L.g, ARCANE_L.b, 0.6))

	# robe : silhouette trapézoïdale franche avec accent de taille
	_trapezoid_o(img, 16, 15, 24, 1.6, 3.2, dress_d)
	_trapezoid(img, 16, 16, 23, 1.1, 2.6, dress)
	_rect(img, 14, 17, 4, 1, ARCANE_L)

	# tête avec silhouette de cheveux
	_disc_o(img, 16, 11, 2.9, ROSE_D, INK)
	_ellipse(img, 16, 11, 2.0, 2.3, skin)
	_tri_up(img, 13, 9, 1, 3, ROSE_D); _tri_up(img, 19, 9, 1, 3, ROSE_D)
	_px(img, 15, 11, INK); _px(img, 17, 11, INK)
	_glow(img, 16.0, 10.7, 2.1, CYAN_L, 0.5)

	# baguette + traînée d'étincelles
	_line(img, 19, 18, 22, 21, GOLD_D); _px(img, 22, 21, GOLD_L)
	_px(img, 16, 5, GOLD_L); _px(img, 12, 8, CYAN_L); _px(img, 20, 8, CYAN_L)

func _fig_drake(img: Image) -> void:
	_ground_shadow(img)
	var sc := Color(0.55, 0.40, 0.40)
	var sc_d := sc.darkened(0.45)
	var sc_l := sc.lightened(0.20)
	var wing_mem := Color(0.55, 0.30, 0.30, 0.75)

	# queue effilée avec pointe en fer de lance
	_line(img, 24, 23, 30, 27, sc_d); _line(img, 24, 22, 30, 26, sc)
	_tri_up(img, 30, 29, 2, 3, sc_d)

	# aile repliée (derrière le corps) - membrane entre les "doigts"
	_trapezoid(img, 21, 12, 22, 1.0, 9.0, sc_d.darkened(0.1))
	for fx in [15, 19, 23, 27]:
		_line(img, 21, 13, fx, 21, wing_mem)
	_line(img, 21, 12, 27, 14, sc_d)

	# pattes avec petites griffes
	_rect(img, 13, 24, 3, 4, sc_d); _rect(img, 19, 24, 3, 4, sc_d)
	_tri_up(img, 13, 28, 1, 2, BONE); _tri_up(img, 21, 28, 1, 2, BONE)

	# corps serpentiforme avec crête dorsale
	_ellipse(img, 17, 21, 9.3, 5.3, sc_d); _ellipse(img, 17, 21, 8.0, 4.3, sc)
	_ellipse(img, 21, 19, 4.0, 3.2, sc_l)
	for rx in [12, 15, 18, 21]:
		_tri_up(img, rx, 17, 1, 2, sc_d)

	# tête avec mâchoire + cornes, museau projeté vers l'avant
	_disc_o(img, 11, 12, 4.5, sc_d, INK); _disc(img, 11, 12, 3.6, sc)
	_rect(img, 4, 12, 7, 3, sc_l); _rect(img, 4, 14, 7, 1, sc_d)
	_tri_up(img, 12, 9, 1, 4, sc_d); _tri_up(img, 9, 9, 1, 3, sc_d)
	_glow_eyes(img, 11, 11, GOLD_L, 1)

	_glow(img, 2.7, 13.3, 3.5, EMBER, 0.6)
	_px(img, 3, 13, EMBER_L); _px(img, 1, 12, GOLD_L); _px(img, 1, 15, EMBER)

func _fig_coffre(img: Image) -> void:
	_ground_shadow(img)
	var wood: Color = Color(0.45, 0.32, 0.20)
	var wood_d: Color = wood.darkened(0.4)
	_rect(img, 7, 16, 19, 12, INK)
	_rect(img, 8, 17, 16, 9, wood)
	_rect(img, 8, 11, 16, 7, wood_d); _rect(img, 8, 11, 16, 1, wood.lightened(0.15))
	_rect(img, 7, 16, 19, 1, GOLD_D); _rect(img, 15, 15, 3, 5, GOLD)
	_px(img, 15, 16, GOLD_L); _px(img, 16, 17, INK); _px(img, 9, 12, wood.lightened(0.2))

func _fig_mimic(img: Image) -> void:
	_fig_coffre(img)
	_rect(img, 8, 16, 16, 4, Color(0.10, 0.04, 0.06))
	for tx in range(6, 18, 2):
		_tri_up(img, tx + 1, 16, 1, 3, BONE)
		_px(img, tx + 1, 19, BONE); _px(img, tx + 1, 17, BONE)
	_ellipse(img, 16, 20, 2.9, 1.6, BLOOD)
	_glow_eyes(img, 16, 12, EMBER, 4)

# --- Boss (Pass 2) -----------------------------------------------------------
func _fig_roi_liche(img: Image) -> void:
	_glow(img, 16.0, 17.3, 12.7, ARCANE, 0.32)
	_rect(img, 5, 8, 21, 21, INK)
	_rect(img, 7, 9, 19, 19, Color(0.28, 0.28, 0.40))
	_rect(img, 7, 7, 3, 7, BONE_D); _rect(img, 24, 7, 3, 7, BONE_D)
	_tri_up(img, 7, 8, 1, 4, BONE); _tri_up(img, 24, 8, 1, 4, BONE)
	_trapezoid_o(img, 16, 16, 28, 4.3, 8.0, ARCANE.darkened(0.42))
	_trapezoid(img, 16, 17, 27, 3.2, 6.4, ARCANE.darkened(0.16))
	_disc_o(img, 16, 12, 4.5, BONE_D, INK); _disc(img, 16, 11, 3.6, BONE)
	_rect(img, 13, 11, 3, 3, INK); _rect(img, 17, 11, 3, 3, INK)
	_glow(img, 14.0, 11.3, 1.7, ARCANE_L, 0.7); _glow(img, 19.3, 11.3, 1.7, ARCANE_L, 0.7)
	_px(img, 13, 11, ARCANE_L); _px(img, 19, 11, ARCANE_L)
	_rect(img, 12, 5, 8, 1, GOLD_D)
	for fx in [12, 16, 20]:
		_glow(img, fx, 2.7, 2.1, ARCANE, 0.7)
		_tri_up(img, fx, 5, 1, 4, INK_SOFT); _px(img, fx, 1, ARCANE_L)

func _fig_seigneur_fantome(img: Image) -> void:
	_glow(img, 16.0, 14.7, 12.0, CYAN, 0.4)
	_disc_o(img, 16, 11, 6.1, CYAN.darkened(0.4), INK_SOFT)
	_disc(img, 16, 11, 5.1, CYAN.darkened(0.12))
	_trapezoid(img, 16, 15, 29, 6.0, 9.3, CYAN.darkened(0.16))
	for x in range(7, 27):
		var cut: int = 29 - (x % 4)
		for y in range(cut, TILE):
			_px(img, x, y, Color(0, 0, 0, 0))
	_ellipse(img, 16, 11, 3.5, 2.9, Color(0.05, 0.08, 0.10))
	_glow_eyes(img, 16, 9, Color(1, 1, 1), 3)
	for p in [Vector2i(4, 8), Vector2i(28, 8), Vector2i(5, 19), Vector2i(27, 19)]:
		_glow(img, p.x, p.y, 2.7, CYAN_L, 0.7); _disc(img, p.x, p.y, 1.3, CYAN_L)
	_fade(img, 0.85)

func _fig_wyrm(img: Image) -> void:
	_ground_shadow(img)
	var sc := Color(0.55, 0.42, 0.40)
	var sc_d := sc.darkened(0.45)
	var sc_l := sc.lightened(0.18)

	# spirale ouverte (rayon décroissant) plutôt qu'un anneau fermé en "donut"
	var n := 26
	for i in range(n):
		var t: float = float(i) / float(n - 1)
		var a: float = t * PI * 1.35 + PI * 0.25
		var rad: float = 7.5 - 4.5 * t
		var seg_r: float = 2.9 - 1.6 * t
		var x: int = int(16 + rad * cos(a))
		var y: int = int(20 + rad * 0.72 * sin(a))
		_disc(img, x, y, seg_r + 0.8, sc_d)
	for i in range(n):
		var t2: float = float(i) / float(n - 1)
		var a2: float = t2 * PI * 1.35 + PI * 0.25
		var rad2: float = 7.5 - 4.5 * t2
		var seg_r2: float = 2.9 - 1.6 * t2
		var x2: int = int(16 + rad2 * cos(a2))
		var y2: int = int(20 + rad2 * 0.72 * sin(a2))
		_disc(img, x2, y2, seg_r2, sc if i % 2 == 0 else sc_l.lerp(sc, 0.5))

	# tête à l'extrémité large de la spirale, avec cornes
	_disc_o(img, 22, 12, 4.5, sc_d, INK); _disc(img, 22, 12, 3.6, sc)
	_rect(img, 24, 11, 4, 3, sc_l)
	_tri_up(img, 20, 9, 1, 4, sc_d); _tri_up(img, 24, 9, 1, 3, sc_d)
	_glow_eyes(img, 22, 11, GOLD_L, 1)
	_glow(img, 22.0, 15.3, 2.3, EMBER, 0.5); _px(img, 22, 15, EMBER_L)

func _fig_araignee_mere(img: Image) -> void:
	_ground_shadow(img)
	var leg: Color = POISON.darkened(0.5)
	for ey in [11, 15, 20, 24]:
		_line(img, 9, 19, 1, ey, leg); _line(img, 23, 19, 31, ey, leg)
	_disc_o(img, 16, 20, 9.3, POISON.darkened(0.45), INK)
	_disc(img, 16, 20, 8.0, POISON.darkened(0.1))
	for p in [Vector2i(13, 19), Vector2i(19, 19), Vector2i(16, 23), Vector2i(12, 21), Vector2i(20, 21)]:
		_disc(img, p.x, p.y, 1.6, Color(0.85, 0.95, 0.7, 0.9)); _px(img, p.x, p.y, Color(1, 1, 1))
	_disc_o(img, 16, 11, 4.8, POISON.darkened(0.3), INK); _disc(img, 16, 11, 3.9, POISON.darkened(0.02))
	_glow_eyes(img, 16, 9, BLOOD, 3); _glow_eyes(img, 16, 12, BLOOD, 1)

func _fig_troll_ancestral(img: Image) -> void:
	_ground_shadow(img)
	var sk: Color = Color(0.42, 0.58, 0.44)
	var sk_d: Color = sk.darkened(0.42)
	_trapezoid_o(img, 15, 9, 29, 8.7, 11.3, sk_d)
	_trapezoid(img, 15, 11, 28, 7.3, 9.3, sk)
	_rect(img, 8, 17, 15, 4, sk.lightened(0.1))
	for rp in [Vector2i(9, 23), Vector2i(13, 16), Vector2i(19, 19), Vector2i(21, 24), Vector2i(16, 12)]:
		_glow(img, rp.x, rp.y, 2.4, CYAN, 0.55); _px(img, rp.x, rp.y, CYAN_L)
	for mp in [Vector2i(11, 13), Vector2i(20, 15)]:
		_disc(img, mp.x, mp.y, 1.7, POISON.darkened(0.2))
	_disc_o(img, 15, 8, 6.1, sk_d, INK); _disc(img, 15, 8, 5.1, sk)
	_rect(img, 8, 9, 13, 1, INK)
	_glow_eyes(img, 15, 8, EMBER, 4)
	_tri_up(img, 11, 15, 1, 5, BONE); _tri_up(img, 19, 15, 1, 5, BONE)

func _fig_paladin_dechu(img: Image) -> void:
	_ground_shadow(img)
	var st: Color = Color(0.78, 0.74, 0.58)
	var st_d: Color = st.darkened(0.4)
	for i in range(0, 12):
		if i % 3 == 0:
			continue
		var a: float = i / 12.0 * PI * 2.0
		_px(img, int(16 + 7 * cos(a)), int(7 + 4 * sin(a)), INK_SOFT)
	_glow(img, 16.0, 6.7, 4.0, ARCANE, 0.3)
	_trapezoid_o(img, 16, 13, 28, 5.3, 8.0, st_d)
	_trapezoid(img, 16, 15, 27, 4.3, 6.4, st)
	_rect(img, 12, 17, 8, 5, st.lightened(0.12))
	_line(img, 16, 16, 19, 25, st_d)
	_disc_o(img, 16, 11, 4.5, st_d, INK); _disc(img, 16, 11, 3.6, st)
	_rect(img, 12, 11, 8, 1, INK)
	_glow_eyes(img, 16, 11, ARCANE_L, 3)
	_rect(img, 5, 12, 1, 13, STEEL_L); _rect(img, 4, 21, 4, 1, GOLD)

func _fig_sorciere(img: Image) -> void:
	_ground_shadow(img)
	var robe: Color = Color(0.45, 0.30, 0.42)
	_rect(img, 7, 7, 1, 21, BONE_D); _rect(img, 25, 7, 1, 21, BONE_D)
	_rect(img, 7, 7, 20, 1, BONE_D); _rect(img, 7, 27, 20, 1, BONE_D)
	for bx in range(9, 25, 4):
		_rect(img, bx, 7, 1, 21, Color(BONE_D.r, BONE_D.g, BONE_D.b, 0.5))
	_trapezoid_o(img, 16, 15, 25, 2.7, 5.6, robe.darkened(0.4))
	_trapezoid(img, 16, 16, 24, 1.9, 4.5, robe)
	_disc_o(img, 16, 11, 3.7, robe.darkened(0.45), INK)
	_ellipse(img, 16, 11, 2.4, 2.1, SKIN.darkened(0.15))
	_px(img, 15, 11, INK); _px(img, 17, 11, INK)
	_tri_up(img, 16, 8, 3, 5, robe.darkened(0.3))
	_glow(img, 16.0, 10.7, 1.9, POISON, 0.4)

func _fig_bourreau(img: Image) -> void:
	_ground_shadow(img)
	var cloth: Color = Color(0.30, 0.28, 0.32)
	_trapezoid_o(img, 15, 11, 28, 6.0, 8.7, cloth.darkened(0.4))
	_trapezoid(img, 15, 12, 27, 4.8, 6.9, cloth)
	_rect(img, 11, 16, 11, 5, cloth.lightened(0.12))
	_disc_o(img, 15, 9, 4.8, cloth.darkened(0.45), INK)
	_disc(img, 15, 9, 3.9, Color(0.20, 0.18, 0.22))
	_rect(img, 12, 9, 7, 1, INK)
	_glow_eyes(img, 15, 9, BLOOD, 3)
	_rect(img, 24, 4, 1, 24, Color(0.36, 0.25, 0.18))
	_rect(img, 20, 4, 7, 8, STEEL_D); _rect(img, 21, 5, 5, 5, STEEL)
	_rect(img, 21, 5, 5, 1, STEEL_L); _px(img, 20, 7, STEEL_L); _px(img, 20, 8, STEEL_L)

func _fig_oeil_neant(img: Image) -> void:
	_glow(img, 16.0, 16.0, 13.3, ARCANE, 0.4)
	for a in range(0, 360, 45):
		var ar: float = a / 180.0 * PI
		var ex: int = int(16 + 12 * cos(ar))
		var ey: int = int(16 + 12 * sin(ar))
		_line(img, 16, 16, ex, ey, ARCANE.darkened(0.25))
		_px(img, ex, ey, ARCANE)
	_disc_o(img, 16, 16, 8.0, ARCANE.darkened(0.4), INK)
	_disc(img, 16, 16, 6.7, Color(0.85, 0.85, 0.95))
	_disc(img, 16, 16, 3.5, BLOOD.darkened(0.1))
	_glow(img, 16.0, 16.0, 2.7, BLOOD, 0.5)
	_disc(img, 16, 16, 1.6, INK)
	_px(img, 13, 13, Color(1, 1, 1))

func _fig_dieu_bete(img: Image) -> void:
	_ground_shadow(img)
	var body: Color = Color(0.62, 0.45, 0.30)
	var body_d: Color = body.darkened(0.4)
	_glow(img, 16.0, 16.0, 12.0, BLOOD, 0.25)
	_ellipse(img, 16, 21, 9.3, 6.0, body_d); _ellipse(img, 16, 21, 8.0, 4.8, body)
	_rect(img, 9, 25, 3, 4, body_d); _rect(img, 20, 25, 3, 4, body_d)
	_line(img, 24, 23, 29, 16, POISON.darkened(0.2)); _disc(img, 29, 15, 1.9, POISON)
	_px(img, 29, 15, BLOOD)
	_disc_o(img, 16, 11, 4.8, body_d, INK); _disc(img, 16, 11, 3.9, body)
	_rect(img, 15, 12, 4, 3, body.lightened(0.1))
	_glow_eyes(img, 16, 11, EMBER, 3)
	for sx in [11, 21]:
		var tipx: int = sx - 3 if sx < 16 else sx + 3
		var tipx2: int = sx - 5 if sx < 16 else sx + 5
		_line(img, sx, 8, tipx, 1, INK_SOFT)
		_line(img, sx, 5, tipx2, 4, INK_SOFT)
		_glow(img, tipx, 1.3, 2.1, ARCANE, 0.6)
		_px(img, tipx, 1, ARCANE_L)

func _fig_ame(img: Image) -> void:
	_glow(img, 16.0, 16.0, 9.3, CYAN, 0.6)
	_disc_o(img, 16, 15, 4.0, CYAN.darkened(0.3), INK_SOFT)
	_disc(img, 16, 15, 2.9, CYAN_L)
	_trapezoid(img, 16, 17, 25, 2.7, 4.0, CYAN.darkened(0.1))
	for x in range(11, 23):
		var cut: int = 25 - (x % 2)
		for y in range(cut, TILE):
			_px(img, x, y, Color(0, 0, 0, 0))
	_px(img, 15, 13, INK); _px(img, 17, 13, INK)
	_fade(img, 0.85)

func _fig_chaudron(img: Image) -> void:
	_ground_shadow(img)
	var iron: Color = Color(0.22, 0.22, 0.26)
	_disc_o(img, 16, 20, 8.7, iron.darkened(0.3), INK)
	_disc(img, 16, 20, 7.3, iron)
	_ellipse(img, 12, 17, 2.7, 1.9, iron.lightened(0.2))
	_ellipse(img, 16, 15, 8.0, 2.4, INK)
	_ellipse(img, 16, 15, 6.7, 1.7, POISON.darkened(0.2))
	_glow(img, 16.0, 13.3, 4.0, POISON, 0.5)
	for p in [Vector2i(13, 12), Vector2i(17, 11), Vector2i(16, 9)]:
		_disc(img, p.x, p.y, 1.1, POISON.lightened(0.2))
	_rect(img, 8, 24, 16, 3, iron.darkened(0.4))
	_glow(img, 16.0, 25.3, 4.0, EMBER, 0.5)

# --- Butin --------------------------------------------------------------------
func _gen_weapon() -> Image:
	var img := _new(false)
	_rect(img, 13, 4, 5, 17, INK)
	_rect(img, 15, 5, 3, 15, STEEL)
	_rect(img, 15, 5, 1, 15, STEEL_L)
	_tri_up(img, 16, 5, 1, 3, STEEL_L)
	_glow(img, 16.0, 12.0, 5.3, CYAN, 0.30)
	_rect(img, 9, 20, 13, 3, GOLD_D)
	_rect(img, 9, 20, 13, 1, GOLD)
	_px(img, 8, 20, GOLD); _px(img, 23, 20, GOLD)
	_rect(img, 15, 23, 3, 5, Color(0.40, 0.27, 0.18))
	_disc_o(img, 16, 28, 2.1, GOLD, GOLD_D)
	_px(img, 16, 27, GOLD_L)
	return img

func _gen_armor() -> Image:
	var img := _new(false)
	_trapezoid(img, 16, 4, 16, 9.3, 10.7, STEEL_D)
	_trapezoid(img, 16, 5, 16, 8.0, 9.3, STEEL)
	for y in range(12, 22):
		var w := int(round(8.0 * (1.0 - float(y - 12) / 9.5)))
		_rect(img, 12 - w, y, 1, 1, STEEL_D)
		_rect(img, 12 + w, y, 1, 1, STEEL_D)
		if w > 1:
			_rect(img, 12 - w + 1, y, (w - 1) * 2, 1, STEEL)
	_rect(img, 11, 7, 3, 11, STEEL_L)
	_glow(img, 16.0, 13.3, 4.0, ARCANE, 0.5)
	_disc_o(img, 16, 13, 3.2, ARCANE, INK_SOFT)
	_disc(img, 16, 13, 1.7, ARCANE_L)
	for ry in [5, 9, 13]:
		_px(img, 8, ry, STEEL_L)
		_px(img, 24, ry, STEEL_L)
	return img

func _gen_relic() -> Image:
	var img := _new(false)
	_disc_o(img, 16, 20, 8.0, GOLD, GOLD_D)
	_disc(img, 16, 20, 4.0, Color(0, 0, 0, 0))
	_px(img, 12, 16, GOLD_L)
	_glow(img, 16.0, 8.0, 4.5, CYAN, 0.7)
	_disc_o(img, 16, 8, 4.0, CYAN, INK_SOFT)
	_disc(img, 16, 8, 2.3, CYAN_L)
	_px(img, 15, 7, Color(1, 1, 1))
	_px(img, 16, 3, CYAN_L); _px(img, 11, 8, CYAN_L); _px(img, 21, 8, CYAN_L)
	return img

func _gen_artifact() -> Image:
	var img := _new(false)
	_glow(img, 16.0, 16.0, 12.0, ARCANE, 0.45)
	_disc(img, 16, 16, 10.7, Color(ARCANE.r, ARCANE.g, ARCANE.b, 0.28))
	_disc(img, 16, 16, 6.7, Color(ARCANE.r, ARCANE.g, ARCANE.b, 0.30))
	for i in range(10):
		var w := int(round(3.5 * (1.0 - float(i) / 10.0)))
		_rect(img, 12 - w, 12 - i, w * 2 + 1, 1, ARCANE)
		_rect(img, 12 - w, 12 + i, w * 2 + 1, 1, ARCANE)
		_rect(img, 12 - i, 12 - w, 1, w * 2 + 1, ARCANE)
		_rect(img, 12 + i, 12 - w, 1, w * 2 + 1, ARCANE)
	_disc(img, 16, 16, 3.2, ARCANE_L)
	_disc(img, 16, 16, 1.5, Color(1, 1, 1))
	return img

func _gen_potion() -> Image:
	var img := _new(false)
	_rect(img, 13, 4, 5, 3, Color(0.40, 0.28, 0.18))
	_rect(img, 13, 7, 5, 4, STEEL_D)
	_disc_o(img, 16, 20, 8.0, INK_SOFT, INK)
	_disc(img, 16, 20, 6.9, Color(0.55, 0.78, 0.88))
	_glow(img, 16.0, 21.3, 5.9, BLOOD, 0.45)
	_ellipse(img, 16, 23, 5.9, 4.8, BLOOD)
	_ellipse(img, 16, 23, 4.5, 3.5, BLOOD.lightened(0.14))
	_rect(img, 12, 16, 1, 8, Color(1, 1, 1, 0.7))
	_px(img, 19, 15, Color(1, 1, 1, 0.6))
	return img

# --- Icônes de nœud de carte (palette "Les Strates", fond transparent) ---------
func _gen_node_combat() -> Image:
	var img := _new(false)
	_line(img, 7, 25, 24, 7, INK); _line(img, 8, 25, 25, 7, INK)
	_line(img, 7, 24, 23, 7, STEEL); _line(img, 8, 24, 24, 7, STEEL_L)
	_px(img, 25, 5, STEEL_L)
	_line(img, 25, 25, 8, 7, INK); _line(img, 24, 25, 7, 7, INK)
	_line(img, 25, 24, 9, 7, STEEL); _line(img, 24, 24, 8, 7, STEEL_L)
	_px(img, 5, 5, STEEL_L)
	_line(img, 4, 23, 11, 27, GOLD); _line(img, 28, 23, 21, 27, GOLD)
	_disc_o(img, 7, 27, 1.9, GOLD, GOLD_D)
	_disc_o(img, 25, 27, 1.9, GOLD, GOLD_D)
	_glow(img, 16.0, 16.0, 3.2, CYAN_L, 0.7)
	_px(img, 16, 16, Color(1, 1, 1)); _px(img, 16, 15, CYAN_L); _px(img, 17, 16, CYAN_L)
	return img

func _gen_node_boss() -> Image:
	var img := _new(false)
	_line(img, 7, 19, 4, 9, BONE_D); _line(img, 8, 19, 5, 9, BONE)
	_px(img, 4, 8, BONE); _px(img, 5, 7, BONE)
	_line(img, 25, 19, 28, 9, BONE_D); _line(img, 24, 19, 27, 9, BONE)
	_px(img, 28, 8, BONE); _px(img, 27, 7, BONE)
	_rect(img, 8, 19, 17, 7, GOLD_D)
	_rect(img, 8, 19, 17, 1, GOLD_L)
	_rect(img, 9, 20, 15, 4, GOLD)
	_tri_up(img, 11, 19, 3, 5, GOLD); _tri_up(img, 16, 19, 3, 8, GOLD); _tri_up(img, 21, 19, 3, 5, GOLD)
	_px(img, 11, 13, GOLD_L); _px(img, 21, 13, GOLD_L)
	_glow(img, 16.0, 10.7, 3.5, EMBER, 0.75)
	_diamond(img, 16, 11, 3, EMBER.darkened(0.2))
	_diamond(img, 16, 11, 1, EMBER)
	_px(img, 16, 9, GOLD_L)
	_diamond(img, 16, 21, 1, EMBER); _px(img, 16, 21, GOLD_L)
	return img

func _gen_node_elite() -> Image:
	var img := _new(false)
	_tri_up(img, 8, 9, 1, 5, BONE_D); _tri_up(img, 24, 9, 1, 5, BONE_D)
	_px(img, 8, 4, BONE); _px(img, 24, 4, BONE)
	_disc_o(img, 16, 13, 8.0, BONE_D, INK)
	_disc(img, 16, 12, 6.9, BONE)
	_ellipse(img, 12, 8, 2.1, 1.7, Color(1, 1, 0.95))
	_rect(img, 11, 11, 4, 4, INK); _rect(img, 19, 11, 4, 4, INK)
	_glow(img, 12.7, 12.7, 2.4, EMBER, 0.7); _glow(img, 20.7, 12.7, 2.4, EMBER, 0.7)
	_px(img, 12, 12, EMBER); _px(img, 20, 12, EMBER)
	_px(img, 12, 11, GOLD_L); _px(img, 20, 11, GOLD_L)
	_px(img, 16, 16, INK)
	_rect(img, 11, 20, 12, 4, BONE_D); _rect(img, 11, 20, 12, 1, BONE)
	for tx in range(12, 23, 3):
		_rect(img, tx, 20, 1, 4, INK)
	return img

func _gen_node_shop() -> Image:
	var img := _new(false)
	var leather := Color(0.45, 0.32, 0.22)
	var leather_d := leather.darkened(0.35)
	_glow(img, 16.0, 8.0, 3.2, GOLD, 0.55)
	_disc_o(img, 16, 8, 3.1, GOLD, GOLD_D); _px(img, 15, 7, GOLD_L)
	_disc_o(img, 16, 20, 9.3, leather_d, INK)
	_disc(img, 16, 20, 8.0, leather)
	_ellipse(img, 12, 16, 3.1, 2.1, leather.lightened(0.22))
	_rect(img, 11, 11, 11, 3, leather_d)
	_rect(img, 9, 13, 13, 1, GOLD_D); _rect(img, 9, 12, 13, 1, GOLD)
	_diamond(img, 16, 21, 3, GOLD); _px(img, 16, 21, GOLD_L)
	return img

func _gen_node_event() -> Image:
	var img := _new(false)
	_glow(img, 16.0, 16.0, 11.3, ARCANE, 0.45)
	_disc(img, 16, 16, 10.7, Color(ARCANE.r, ARCANE.g, ARCANE.b, 0.25))
	_diamond(img, 16, 16, 9, ARCANE.darkened(0.35))
	_diamond(img, 16, 16, 8, ARCANE)
	_diamond(img, 16, 16, 5, ARCANE.darkened(0.45))
	_rect(img, 13, 11, 5, 1, CYAN_L)
	_px(img, 17, 12, CYAN_L); _px(img, 17, 13, CYAN_L)
	_px(img, 16, 15, CYAN_L); _px(img, 16, 16, CYAN_L)
	_px(img, 16, 17, CYAN_L)
	_glow(img, 16.0, 20.0, 1.9, Color(1, 1, 1), 0.8); _px(img, 16, 20, Color(1, 1, 1))
	return img

func _gen_node_rest() -> Image:
	var img := _new(false)
	var wood := Color(0.45, 0.32, 0.21)
	var wood_l := Color(0.55, 0.40, 0.27)
	_line(img, 7, 25, 21, 20, INK); _line(img, 25, 25, 11, 20, INK)
	_line(img, 7, 24, 21, 19, wood); _line(img, 8, 24, 23, 19, wood_l)
	_line(img, 25, 24, 11, 19, wood); _line(img, 24, 24, 9, 19, wood_l)
	_px(img, 7, 24, wood_l); _px(img, 25, 24, wood_l)
	_glow(img, 16.0, 16.0, 6.7, EMBER, 0.55)
	_tri_up(img, 16, 20, 5, 13, EMBER.darkened(0.25))
	_tri_up(img, 16, 20, 4, 11, EMBER)
	_tri_up(img, 16, 19, 3, 8, GOLD)
	_px(img, 16, 11, GOLD_L)
	_px(img, 13, 17, EMBER.lightened(0.1)); _px(img, 19, 17, EMBER)
	_px(img, 12, 24, EMBER); _px(img, 20, 24, GOLD)
	return img

# --- Terrain par biome --------------------------------------------------------
func _gen_ground(a: Color, b: Color) -> Image:
	var img := _new(true)
	img.fill(a)
	var joint_outer := a.darkened(0.42).lerp(INK, 0.55)
	var joint_inner := a.darkened(0.22).lerp(INK_SOFT, 0.35)
	for i in TILE:
		_px(img, i, 0, joint_outer);  _px(img, 0, i, joint_outer)
		_px(img, i, 16, joint_inner); _px(img, 16, i, joint_inner)
	for i in TILE:
		_px(img, i, 1, a.lightened(0.10)); _px(img, 1, i, a.lightened(0.10))
		_px(img, i, 17, a.lightened(0.06)); _px(img, 17, i, a.lightened(0.06))
	for i in TILE:
		_px(img, i, 15, a.darkened(0.16)); _px(img, 15, i, a.darkened(0.16))
	# Grain tramé (Bayer) : transitions douces sans bruit criard.
	for y in TILE:
		for x in TILE:
			var thr: float = (BAYER4[y & 3][x & 3] + 0.5) / 16.0
			var r := rng.randf()
			if r > 0.90 and 0.5 > thr:
				_px(img, x, y, b)
			elif r < 0.06:
				_px(img, x, y, a.darkened(0.22))
			elif (x * 5 + y * 3) % 17 == 0:
				_px(img, x, y, a.lightened(0.06))
	for p in [Vector2i(3, 3), Vector2i(19, 3), Vector2i(3, 19), Vector2i(19, 19)]:
		_px(img, p.x, p.y, b.lightened(0.14))
	for i in range(9):
		_px(img, i, 0, a.lightened(0.09)); _px(img, 0, i, a.lightened(0.07))
	var edge := a.darkened(0.40).lerp(INK_SOFT, 0.5)
	for i in TILE:
		_px(img, i, TILE - 1, edge)
		_px(img, TILE - 1, i, edge)
	return img

func _gen_tree(trunk: Color, leaf: Color, style: String) -> Image:
	var img := _new(false)
	var tk  := trunk
	var tk_d := trunk.darkened(0.45)
	var tk_l := trunk.lightened(0.18)
	var lf   := leaf
	var lf_d := leaf.darkened(0.42)
	var lf_l := leaf.lightened(0.28)
	var lf_h := leaf.lightened(0.50)
	match style:
		"round":
			# Root bumps (anchor sprite to ground)
			_ellipse(img, 13, 29, 2.5, 1.4, tk_d)
			_ellipse(img, 19, 29, 2.0, 1.2, tk_d)
			_ellipse(img, 16, 30, 3.2, 1.3, tk_d)
			# Trunk — wide base, narrows upward, bark texture
			_trapezoid(img, 16, 16, 30, 2.0, 3.8, tk_d)
			_trapezoid(img, 16, 16, 29, 1.2, 2.8, tk)
			_rect(img, 16, 16, 1, 13, tk_l)   # light left edge
			_px(img, 15, 20, tk_d); _px(img, 17, 24, tk_d)   # bark knots
			_px(img, 16, 22, tk_l); _px(img, 15, 26, tk_l)
			# Side branch stubs (gnarled feel)
			_rect(img, 10, 20, 5, 1, tk_d); _rect(img, 11, 20, 3, 1, tk)
			_rect(img, 20, 23, 4, 1, tk_d); _rect(img, 20, 23, 3, 1, tk)
			# Leaf canopy — left(lit)->right(shadow) gradient instead of a flat fill
			_disc_o(img, 16, 13, 11.0, lf_d, INK_SOFT)
			_disc_band(img, 16, 13, 9.5, lf_l, lf, lf_d)
			# Secondary cluster top-left (bright spot = sun side)
			_disc(img, 11, 9,  4.5, lf_l)
			_disc(img, 11, 9,  2.4, lf_h)
			# Secondary cluster right
			_disc(img, 21, 11, 3.2, lf_l)
			# Highlight pixels (sparkling leaf tips)
			_px(img, 9,  7,  lf_h); _px(img, 10, 6, lf_l)
			_px(img, 19, 5,  lf_l); _px(img, 23, 9, lf_h)
			# Shadow underside
			_ellipse(img, 16, 20, 7.0, 2.2, lf_d)
		"pine":
			var cone := Color(0.32, 0.20, 0.12)
			# Trunk with bark striations
			_rect(img, 14, 25, 4, 6, tk_d)
			_rect(img, 15, 25, 2, 6, tk)
			_px(img, 14, 27, tk_d); _px(img, 17, 29, tk_d); _px(img, 15, 28, tk_l)
			# Branch tiers bottom → top: crisp silhouette + lit->shadow gradient
			var tiers := [[16, 28, 10, 10], [16, 21, 8, 8], [16, 15, 6, 7], [16, 10, 4, 6], [16, 6, 2, 4]]
			for tier in tiers:
				var cx: int = tier[0]; var base_y: int = tier[1]; var hw: int = tier[2]; var h: int = tier[3]
				_tri_up(img, cx, base_y, hw + 1, h + 1, INK_SOFT)
				_tri_band(img, cx, base_y, hw, h, lf_l, lf, lf_d)
				_px(img, cx - hw + 1, base_y - 1, lf_l)
				_px(img, cx + hw - 1, base_y - 1, lf_d)
			# Hanging pinecones for prop detail
			_ellipse(img, 12, 23, 1.1, 1.6, cone); _ellipse(img, 21, 17, 1.0, 1.4, cone)
			# Subtle highlight flecks
			_px(img, 13, 24, lf_h); _px(img, 12, 17, lf_h); _px(img, 13, 12, lf_h); _px(img, 14, 8, lf_h)
			_px(img, 15, 5,  lf_h)
		"cactus":
			# Main stem
			_rect(img, 13, 5, 6, 25, lf_d)
			_rect(img, 14, 5, 5, 25, lf)
			_rect(img, 15, 5, 2, 25, lf_l)
			# Left arm
			_rect(img, 7, 12, 7, 3, lf_d); _rect(img, 7, 12, 7, 2, lf)
			_rect(img, 7, 9,  3, 5, lf_d);  _rect(img, 8, 9,  2, 5, lf)
			# Right arm
			_rect(img, 19, 15, 6, 3, lf_d); _rect(img, 19, 15, 6, 2, lf)
			_rect(img, 22, 11, 3, 6, lf_d);  _rect(img, 23, 11, 2, 6, lf)
			# Spine dots
			for yy in range(7, 28, 4):
				_px(img, 14, yy, lf_l)
				_px(img, 13, yy + 2, lf_d)
			# Arm-tip ridge highlights + a small desert flower for accent
			_px(img, 8, 9, lf_h); _px(img, 24, 11, lf_h)
			_disc(img, 9, 8, 1.1, ROSE); _px(img, 9, 8, ROSE_L)
		"dead":
			# Main trunk (gnarled, slightly off-center)
			_rect(img, 15, 4, 3, 27, tk_d)
			_rect(img, 15, 4, 2, 27, tk)
			_rect(img, 15, 4, 1, 20, tk_l)
			# Branch left mid
			_rect(img, 8, 15, 7, 1, tk_d); _rect(img, 9, 15, 6, 1, tk)
			_rect(img, 8, 11, 1, 5, tk_d); _rect(img, 9, 11, 1, 4, tk)
			_rect(img, 7, 10, 2, 2, tk_d)   # branch tip
			# Branch right upper
			_rect(img, 17, 12, 7, 1, tk_d); _rect(img, 17, 12, 6, 1, tk)
			_rect(img, 23, 8,  1, 5, tk_d); _rect(img, 22, 9,  1, 4, tk)
			# Twig ends
			_px(img, 6,  10, tk_d); _px(img, 8, 9, tk_d)
			_px(img, 24,  7, tk_d); _px(img, 22, 8, tk_d)
			# Crown spread
			_rect(img, 13, 4, 5, 2, tk)
			# Bark knots + bare twig forks for extra texture
			_px(img, 16, 16, tk_d); _px(img, 15, 22, tk_d); _px(img, 16, 9, tk_l)
			_line(img, 9, 14, 7, 12, tk_d); _line(img, 23, 11, 25, 9, tk_d)
		_:
			_disc_o(img, 16, 16, 8.5, lf_d, INK_SOFT)
			_disc_band(img, 16, 16, 7.0, lf_l, lf, lf_d)
			_disc(img, 12, 12, 3.5, lf_l)
			_px(img, 11, 11, lf_h)
	return img

func _gen_rock(c: Color) -> Image:
	var img := _new(false)
	var c_d := c.darkened(0.42)
	var c_dd := c.darkened(0.58)
	var c_l := c.lightened(0.30)
	var c_ll := c.lightened(0.50)
	var moss := Color(0.40, 0.62, 0.30)

	_ellipse(img, 16, 29, 9.5, 2.2, Color(INK.r, INK.g, INK.b, 0.30))   # ombre de contact

	# petit bloc compagnon (arrière-gauche), dessiné avant pour que le rocher principal le chevauche
	_ellipse(img, 9, 21, 4.3, 3.6, INK_SOFT)
	_ellipse(img, 9, 21, 3.4, 2.8, c_d)
	_ellipse(img, 8, 19, 1.3, 1.0, c_l)

	# rocher principal
	_ellipse(img, 17, 19, 11.0, 8.4, INK_SOFT)
	_ellipse(img, 17, 19, 9.7, 7.2, c)
	_ellipse(img, 13, 14, 3.8, 2.7, c_l)             # plaque de lumière haut-gauche
	_ellipse(img, 12, 13, 1.6, 1.1, c_ll)            # cœur spéculaire
	_ellipse(img, 21, 23, 3.6, 2.6, c_dd)            # ombre bas-droite

	# fissures irrégulières plutôt que des rects droits
	_line(img, 18, 12, 17, 17, c_dd); _line(img, 17, 17, 19, 22, c_dd)
	_line(img, 10, 18, 13, 20, c_dd)

	# petits cailloux à la base (blobs 2x2, pas des cercles à 1px qui créent des croix)
	_rect(img, 23, 24, 2, 2, c_d); _px(img, 23, 24, c_l)
	_rect(img, 21, 26, 2, 2, c); _px(img, 21, 26, c_l)
	_rect(img, 4, 24, 2, 2, c_d); _px(img, 4, 24, c_l)

	# touffes de mousse le long du sommet
	_rect(img, 18, 12, 2, 2, moss); _rect(img, 19, 13, 2, 1, moss.darkened(0.15))
	_rect(img, 9, 17, 2, 2, moss.darkened(0.1))
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
			_rect(img, 16, 19, 1, 8, POISON.darkened(0.2))
			_glow(img, 16.0, 16.0, 2.9, c, 0.45)
			_disc_o(img, 16, 16, 3.2, c, INK_SOFT)
			_px(img, 16, 16, GOLD_L)
		"mushroom":
			_rect(img, 16, 21, 3, 5, BONE)
			_glow(img, 17.3, 17.3, 4.0, c, 0.35)
			_ellipse(img, 17, 19, 5.6, 3.7, c.darkened(0.25))
			_ellipse(img, 17, 17, 4.5, 2.7, c)
			_px(img, 15, 17, Color(1, 1, 1)); _px(img, 19, 19, Color(1, 1, 1))
		"bones":
			_rect(img, 11, 21, 11, 1, BONE)
			_rect(img, 11, 20, 1, 4, BONE); _rect(img, 20, 20, 1, 4, BONE)
			_px(img, 9, 20, BONE_D); _px(img, 21, 20, BONE_D)
		"crystal":
			_glow(img, 16.0, 17.3, 5.3, c, 0.6)
			_diamond(img, 16, 19, 5, c.darkened(0.3))
			_diamond(img, 16, 19, 4, c)
			_rect(img, 16, 15, 1, 8, c.lightened(0.48))
			_px(img, 15, 16, Color(1, 1, 1))
		"reed":
			for sx in [12, 16, 20]:
				_rect(img, sx, 15, 1, 12, c.darkened(0.15))
				_ellipse(img, sx, 13, 1.9, 3.2, c.darkened(0.3))
		"ember":
			_glow(img, 16.0, 21.3, 5.3, EMBER, 0.6)
			_ellipse(img, 16, 23, 4.5, 2.7, INK_SOFT)
			_ellipse(img, 16, 21, 3.2, 2.1, EMBER.darkened(0.2))
			_ellipse(img, 16, 21, 1.9, 1.3, EMBER)
			_px(img, 16, 19, GOLD_L)
		_:
			_disc_o(img, 16, 19, 2.7, c, INK_SOFT)
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
		_ellipse(img, x, y, 1.9, 1.5, Color(0.40, 0.36, 0.33))
		_px(img, x - 1, y - 1, Color(0.50, 0.46, 0.42))
	return img
