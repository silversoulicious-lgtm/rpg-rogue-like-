extends SceneTree
# Générateur d'assets pixel-art — IDENTITÉ VISUELLE "Les Strates".
# Palette restreinte et tranchée (indigo profond + accents arcaniques), façon
# Moonring : silhouettes lisibles, contour sombre cohérent, lumière en haut-gauche.
# Lancé en headless : godot --headless --script res://_assets_gen.gd
# Produit des PNG 24x24 dans res://assets/.

const TILE := 24
var rng := RandomNumberGenerator.new()

# --- PALETTE D'IDENTITÉ -------------------------------------------------------
const INK      := Color(0.078, 0.071, 0.118)   # contour / ombre (near-black indigo)
const INK_SOFT := Color(0.13, 0.12, 0.19)
const STONE    := Color(0.227, 0.212, 0.306)
const STONE_D  := Color(0.149, 0.137, 0.212)
const STONE_L  := Color(0.32, 0.30, 0.42)
const FLOOR_A  := Color(0.118, 0.110, 0.165)
const FLOOR_B  := Color(0.157, 0.145, 0.220)
const STEEL    := Color(0.588, 0.627, 0.725)
const STEEL_D  := Color(0.361, 0.392, 0.490)
const STEEL_L  := Color(0.78, 0.82, 0.90)
const BONE     := Color(0.839, 0.824, 0.737)
const BONE_D   := Color(0.60, 0.58, 0.49)
const GOLD     := Color(0.882, 0.706, 0.275)
const GOLD_D   := Color(0.588, 0.431, 0.137)
const GOLD_L   := Color(1.0, 0.87, 0.5)
const BLOOD    := Color(0.745, 0.216, 0.235)
const BLOOD_D  := Color(0.49, 0.13, 0.16)
const ARCANE   := Color(0.588, 0.373, 0.824)
const ARCANE_L := Color(0.784, 0.588, 0.961)
const CYAN     := Color(0.373, 0.824, 0.863)
const CYAN_L   := Color(0.65, 0.95, 1.0)
const POISON   := Color(0.471, 0.784, 0.353)
const EMBER    := Color(0.941, 0.549, 0.216)

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

# Ombre de contact douce au pied d'une figure (ancre la silhouette au sol).
func _ground_shadow(img: Image) -> void:
	_ellipse(img, 12, 21, 6.5, 1.8, Color(INK.r, INK.g, INK.b, 0.30))

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
	# Dallage : grain subtil + variations froides.
	for y in TILE:
		for x in TILE:
			var r := rng.randf()
			if r < 0.10:
				_px(img, x, y, FLOOR_A.darkened(0.22))
			elif r > 0.92:
				_px(img, x, y, FLOOR_B)
	# Joints de dalle (croix décentrée) pour un motif de pierre.
	for i in TILE:
		_px(img, i, 0, INK)
		_px(img, 0, i, INK)
		_px(img, i, 12, INK_SOFT.darkened(0.1))
		_px(img, 12, i, INK_SOFT.darkened(0.1))
	# Reflet froid en haut-gauche de chaque quart.
	_px(img, 2, 2, FLOOR_B.lightened(0.10))
	_px(img, 14, 2, FLOOR_B.lightened(0.10))
	return img

func _gen_wall() -> Image:
	var img := _new(true)
	img.fill(STONE)
	var brick_h := 6
	var brick_w := 8
	var row := 0
	for by in range(0, TILE, brick_h):
		for x in TILE:
			_px(img, x, by, INK)                  # joint horizontal sombre
			_px(img, x, by + 1, STONE_L)          # liseré éclairé sous le joint
		var off := (brick_w / 2) if (row % 2 == 1) else 0
		var bx := -off
		while bx <= TILE:
			for yy in range(by, by + brick_h):
				_px(img, bx, yy, INK)             # joint vertical
			# ombrage interne de la brique (bas-droite)
			for yy in range(by + 2, by + brick_h):
				_px(img, bx + brick_w - 1, yy, STONE_D)
			bx += brick_w
		row += 1
	# Grain + rares cristaux arcaniques incrustés (identité de la Tour).
	for i in 26:
		_px(img, rng.randi_range(0, TILE - 1), rng.randi_range(0, TILE - 1), STONE_D)
	for i in 2:
		var cx := rng.randi_range(4, TILE - 5)
		var cy := rng.randi_range(4, TILE - 5)
		_px(img, cx, cy, ARCANE)
		_px(img, cx, cy - 1, ARCANE_L)
	return img

func _gen_stairs() -> Image:
	var img := _new(false)                        # transparent : posé sur le sol
	# Portail d'ascension : arche sombre + lueur arcanique + chevron doré.
	_disc_o(img, 12, 13, 9.0, INK_SOFT, INK)      # masse de l'arche
	_ellipse(img, 12, 14, 6.5, 7.5, Color(ARCANE.r, ARCANE.g, ARCANE.b, 0.55))
	_ellipse(img, 12, 15, 4.5, 5.5, Color(ARCANE_L.r, ARCANE_L.g, ARCANE_L.b, 0.55))
	# Marches suggérées dans la lueur.
	for s in range(3):
		var y := 19 - s * 3
		var w := 5 - s
		_rect(img, 12 - w, y, w * 2, 1, Color(CYAN_L.r, CYAN_L.g, CYAN_L.b, 0.7))
	# Chevron "montée".
	_tri_up(img, 12, 9, 4, 4, GOLD_L)
	_tri_up(img, 12, 11, 4, 3, GOLD)
	return img

# --- Créatures (héroïne & ennemis) -------------------------------------------
# Chaque créature est une petite FIGURE (tête + corps/cape) à silhouette
# distincte, contour INK et lumière en haut-gauche.
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

# Reflet d'œil lumineux générique.
func _glow_eyes(img: Image, cx: int, ey: int, c: Color, spread: int = 3) -> void:
	_rect(img, cx - spread, ey, 2, 2, c)
	_rect(img, cx + spread - 1, ey, 2, 2, c)
	_px(img, cx - spread, ey, c.lightened(0.4))
	_px(img, cx + spread, ey, c.lightened(0.4))

# Héroïne ARIA : sprite signature. Longue chevelure rose, cape arcanique évasée,
# armure légère à liseré cyan, lame luisante, diadème à gemme. Doit ressortir
# nettement face aux ennemis (héroïne = pièce maîtresse de la lisibilité).
const ROSE   := Color(0.92, 0.55, 0.85)
const ROSE_D := Color(0.62, 0.30, 0.56)
const ROSE_L := Color(1.0, 0.74, 0.95)
const SKIN   := Color(0.94, 0.82, 0.72)
const SKIN_D := Color(0.78, 0.62, 0.54)

# Proportions communes aux 3 vues (paper-doll cohérent) : tête y3-10, buste
# y10-18, jambes y18-22, axe central x=12.

# --- Vue de FACE (déplacement vers le bas / par défaut) ---
func _fig_aria(img: Image) -> void:
	_ground_shadow(img)
	# Cape arcanique, juste visible derrière les épaules.
	_trapezoid(img, 12, 11, 21, 3.6, 6.0, ARCANE.darkened(0.4))
	# Jambes / bottes.
	_rect(img, 9, 18, 3, 4, STEEL_D); _rect(img, 9, 18, 3, 1, STEEL)
	_rect(img, 13, 18, 3, 4, STEEL_D); _rect(img, 13, 18, 3, 1, STEEL)
	# Tunique arcanique sous la cuirasse.
	_trapezoid_o(img, 12, 15, 20, 2.6, 4.0, ARCANE.darkened(0.25))
	_rect(img, 12, 16, 1, 4, ARCANE_L.darkened(0.1))       # pli central
	# Cuirasse claire à liseré cyan.
	_trapezoid_o(img, 12, 10, 16, 3.2, 3.6, STEEL_D)
	_trapezoid(img, 12, 11, 15, 2.4, 2.8, STEEL_L)
	_rect(img, 10, 11, 5, 1, CYAN)                          # encolure cyan
	_diamond(img, 12, 13, 2, CYAN); _px(img, 12, 13, Color(1, 1, 1))  # emblème
	# Spallières + bras.
	_disc_o(img, 8, 11, 1.7, STEEL, STEEL_D); _disc_o(img, 16, 11, 1.7, STEEL, STEEL_D)
	_rect(img, 7, 12, 2, 4, ARCANE.darkened(0.1))          # bras G
	_rect(img, 15, 12, 2, 4, ARCANE.darkened(0.1))         # bras D
	_px(img, 7, 15, SKIN); _px(img, 16, 15, SKIN)          # mains
	# Tête : chevelure encadrant un visage net.
	_disc_o(img, 12, 7, 3.7, ROSE_D, INK)                  # masse de cheveux
	_ellipse(img, 12, 8, 2.5, 2.7, SKIN)                   # visage
	_rect(img, 9, 7, 2, 4, ROSE); _rect(img, 14, 7, 2, 4, ROSE)   # mèches latérales
	_px(img, 9, 7, ROSE_L)
	_rect(img, 9, 5, 7, 2, ROSE); _px(img, 10, 5, ROSE_L) # frange
	_rect(img, 10, 7, 5, 1, ROSE_D)                        # ligne de frange
	_px(img, 11, 9, INK); _px(img, 14, 9, INK)             # yeux (nets)
	_px(img, 11, 8, SKIN_D); _px(img, 14, 8, SKIN_D)
	_px(img, 12, 11, SKIN_D)                               # bouche
	# Diadème à gemme.
	_rect(img, 10, 6, 5, 1, GOLD); _px(img, 12, 6, CYAN_L)

# --- Vue de DOS (déplacement vers le haut) ---
func _fig_aria_back(img: Image) -> void:
	_ground_shadow(img)
	# Bottes.
	_rect(img, 9, 18, 3, 4, STEEL_D); _rect(img, 13, 18, 3, 4, STEEL_D)
	# Cape arcanique pleine (le dos montre la cape entière).
	_trapezoid_o(img, 12, 9, 22, 3.6, 7.5, ARCANE.darkened(0.45))
	_trapezoid(img, 12, 10, 21, 2.8, 6.0, ARCANE)
	_rect(img, 12, 10, 1, 11, ARCANE_L.darkened(0.12))     # couture centrale
	_px(img, 9, 13, ARCANE_L.darkened(0.2)); _px(img, 15, 16, ARCANE_L.darkened(0.2))
	# Spallières visibles en haut.
	_disc_o(img, 8, 11, 1.7, STEEL, STEEL_D); _disc_o(img, 16, 11, 1.7, STEEL, STEEL_D)
	_rect(img, 9, 10, 6, 1, CYAN)                           # liseré de col (dos)
	# Tête (arrière de la chevelure) + tresse.
	_disc_o(img, 12, 7, 3.7, ROSE_D, INK)
	_disc(img, 12, 7, 3.1, ROSE)
	_ellipse(img, 10, 5, 1.4, 1.2, ROSE_L)                 # reflet
	_rect(img, 11, 9, 2, 8, ROSE_D); _rect(img, 11, 9, 2, 7, ROSE)   # tresse dans le dos
	_px(img, 11, 12, ROSE_L); _px(img, 12, 15, ROSE_D)
	_rect(img, 9, 6, 6, 1, GOLD)                            # diadème (vu de dos)

# --- Vue de PROFIL (déplacement latéral ; orientée vers la DROITE, miroir à gauche) ---
func _fig_aria_side(img: Image) -> void:
	_ground_shadow(img)
	# Cape qui traîne en arrière (à gauche).
	_trapezoid(img, 9, 11, 21, 2.4, 5.2, ARCANE.darkened(0.45))
	_trapezoid(img, 9, 12, 20, 1.7, 4.0, ARCANE.darkened(0.2))
	_px(img, 5, 20, ARCANE.darkened(0.3))
	# Jambes décalées (pas en avant).
	_rect(img, 11, 18, 3, 4, STEEL_D); _rect(img, 11, 18, 3, 1, STEEL)
	_rect(img, 13, 19, 3, 3, STEEL_D.darkened(0.08))
	# Buste de profil, tourné vers la droite.
	_trapezoid_o(img, 12, 10, 17, 2.4, 3.0, STEEL_D)
	_trapezoid(img, 12, 11, 16, 1.7, 2.2, STEEL_L)
	_rect(img, 13, 12, 3, 1, CYAN)                          # liseré vers l'avant
	_disc_o(img, 11, 11, 1.7, STEEL, STEEL_D)              # épaule (arrière)
	_rect(img, 14, 12, 2, 4, ARCANE.darkened(0.1))         # bras avant
	_px(img, 15, 15, SKIN)                                 # main
	# Tresse fine dans le dos (gauche), tracée AVANT la tête (dégage l'armure).
	_trapezoid_o(img, 9, 9, 19, 1.2, 1.8, ROSE_D)
	_trapezoid(img, 9, 9, 18, 0.7, 1.2, ROSE)
	_px(img, 9, 13, ROSE_L); _px(img, 9, 17, ROSE_D)
	# Tête : la chevelure couvre le crâne et l'arrière ; le visage occupe l'avant
	# (joue/mâchoire vers la droite) — plus d'effet « chauve ».
	_disc_o(img, 12, 7, 3.6, ROSE_D, INK)                  # calotte de cheveux
	_disc(img, 11, 6, 3.0, ROSE)
	_ellipse(img, 10, 5, 1.2, 1.0, ROSE_L)                 # reflet
	_ellipse(img, 14, 8, 2.1, 2.3, SKIN)                   # visage (avant)
	_px(img, 16, 8, SKIN_D)                                # nez
	_rect(img, 14, 8, 1, 2, INK)                           # œil
	_px(img, 15, 11, SKIN_D)                               # menton
	_px(img, 13, 5, ROSE); _px(img, 14, 6, ROSE)          # mèche frontale
	# Diadème (de profil).
	_px(img, 12, 5, GOLD); _px(img, 13, 6, GOLD); _px(img, 14, 7, CYAN_L)

# Classe « chevalier » (legacy) : armure d'acier, écharpe rouge, visière cyan.
func _fig_knight(img: Image) -> void:
	_ground_shadow(img)
	# Cape / corps en acier sombre.
	_trapezoid_o(img, 12, 11, 21, 2.5, 6.0, STEEL_D)
	_trapezoid(img, 12, 12, 20, 1.5, 4.5, STEEL)
	# Écharpe rouge flottante.
	_rect(img, 6, 12, 3, 2, BLOOD)
	_px(img, 5, 13, BLOOD_D)
	_px(img, 8, 11, BLOOD)
	# Plastron + reflet.
	_rect(img, 10, 13, 4, 5, STEEL_L)
	_px(img, 10, 13, STEEL)
	_rect(img, 11, 14, 1, 3, Color(1, 1, 1, 0.55))
	# Tête casquée.
	_disc_o(img, 12, 7, 4.2, STEEL_D, INK)
	_disc(img, 12, 6, 3.4, STEEL)
	_ellipse(img, 10, 5, 1.6, 1.4, STEEL_L)        # reflet haut-gauche
	# Visière lumineuse (cyan).
	_rect(img, 9, 7, 6, 1, CYAN_L)
	_px(img, 9, 7, CYAN)
	# Plumet.
	_tri_up(img, 12, 3, 1, 3, BLOOD)
	# Épée au flanc (lame qui dépasse).
	_rect(img, 17, 9, 1, 9, STEEL_L)
	_rect(img, 16, 16, 3, 1, GOLD)

func _fig_mage(img: Image) -> void:
	_ground_shadow(img)
	# Robe arcanique.
	_trapezoid_o(img, 12, 11, 21, 2.0, 6.5, ARCANE.darkened(0.45))
	_trapezoid(img, 12, 12, 20, 1.2, 5.0, ARCANE)
	_rect(img, 11, 14, 2, 6, ARCANE_L.darkened(0.1))   # plis éclairés
	# Tête.
	_disc_o(img, 12, 8, 3.4, ARCANE.darkened(0.4), INK)
	_disc(img, 12, 8, 2.6, Color(0.86, 0.78, 0.66))    # visage
	_glow_eyes(img, 12, 7, CYAN, 2)
	# Chapeau pointu.
	_trapezoid_o(img, 12, 1, 6, 0.5, 4.5, ARCANE.darkened(0.25))
	_px(img, 12, 1, GOLD_L)                              # étoile au sommet
	_px(img, 9, 6, GOLD)                                 # fermoir
	# Bâton à gemme.
	_rect(img, 6, 8, 1, 12, GOLD_D)
	_disc_o(img, 6, 7, 2.0, CYAN, INK)
	_px(img, 6, 6, CYAN_L)

func _fig_ranger(img: Image) -> void:
	_ground_shadow(img)
	# Manteau vert.
	_trapezoid_o(img, 12, 11, 21, 2.5, 6.0, POISON.darkened(0.5))
	_trapezoid(img, 12, 12, 20, 1.6, 4.6, POISON.darkened(0.25))
	_rect(img, 11, 14, 2, 5, POISON.darkened(0.1))
	# Capuche.
	_disc_o(img, 12, 7, 4.2, POISON.darkened(0.5), INK)
	_ellipse(img, 12, 6, 3.4, 3.6, POISON.darkened(0.3))
	_ellipse(img, 12, 8, 2.4, 2.0, Color(0.10, 0.10, 0.14))   # ombre du visage
	_glow_eyes(img, 12, 8, CYAN_L, 2)
	# Arc.
	for i in range(11):
		var yy := 6 + i
		var dx := int(round(3.0 * sin(float(i) / 10.0 * PI)))
		_px(img, 18 - dx, yy, GOLD_D)
	_rect(img, 18, 6, 1, 11, Color(0.85, 0.85, 0.9, 0.8))     # corde

func _fig_gobelin(img: Image) -> void:
	_ground_shadow(img)
	var skin := POISON.darkened(0.15)
	# Petit corps trapu.
	_trapezoid_o(img, 12, 13, 21, 3.0, 5.5, skin.darkened(0.35))
	_trapezoid(img, 12, 14, 20, 2.0, 4.2, skin)
	_rect(img, 10, 15, 4, 3, Color(0.45, 0.32, 0.22))         # pagne de cuir
	# Grosse tête + oreilles pointues.
	_disc_o(img, 12, 9, 4.0, skin.darkened(0.3), INK)
	_disc(img, 12, 9, 3.2, skin)
	_ellipse(img, 10, 7, 1.3, 1.1, skin.lightened(0.25))
	_tri_up(img, 6, 11, 2, 5, skin.darkened(0.1))             # oreille G
	_tri_up(img, 18, 11, 2, 5, skin.darkened(0.1))            # oreille D
	_glow_eyes(img, 12, 8, GOLD_L, 2)
	_rect(img, 10, 11, 4, 1, INK)                             # bouche
	_px(img, 11, 11, BONE)                                    # croc
	# Dague.
	_rect(img, 18, 13, 1, 5, STEEL_L)

func _fig_wolf(img: Image) -> void:
	_ground_shadow(img)
	var fur := Color(0.40, 0.42, 0.50)
	var fur_d := fur.darkened(0.40)
	var fur_l := fur.lightened(0.18)
	# Corps + arrière-train surélevé (posture de prédateur).
	_ellipse(img, 14, 15, 7.5, 4.4, fur_d)
	_ellipse(img, 14, 15, 6.5, 3.6, fur)
	_ellipse(img, 17, 13, 3.4, 3.0, fur)                      # croupe haute
	_ellipse(img, 16, 12, 2.0, 1.4, fur_l)                    # reflet dorsal
	_rect(img, 9, 18, 2, 3, fur_d)                            # pattes
	_rect(img, 16, 18, 2, 3, fur_d)
	_ellipse(img, 21, 12, 2.6, 1.4, fur_d)                    # queue dressée
	# Tête basse à gauche.
	_disc_o(img, 6, 13, 3.6, fur_d, INK)
	_disc(img, 6, 13, 2.9, fur)
	_tri_up(img, 4, 10, 1, 3, fur_d)                          # oreilles
	_tri_up(img, 8, 10, 1, 3, fur_d)
	_rect(img, 1, 13, 4, 2, fur_l)                            # museau allongé
	_px(img, 1, 14, INK)                                      # truffe
	_rect(img, 5, 12, 2, 1, CYAN_L)                           # œil luisant
	_px(img, 4, 15, BONE)                                     # croc

func _fig_skeleton(img: Image) -> void:
	_ground_shadow(img)
	# Cage thoracique osseuse.
	_trapezoid_o(img, 12, 12, 20, 2.0, 4.0, BONE_D)
	_trapezoid(img, 12, 13, 19, 1.4, 3.0, BONE)
	for ry in [14, 16, 18]:
		_rect(img, 10, ry, 5, 1, INK_SOFT)                    # côtes
	_rect(img, 12, 13, 1, 7, BONE_D)                          # colonne
	# Crâne.
	_disc_o(img, 12, 8, 4.0, BONE_D, INK)
	_disc(img, 12, 7, 3.3, BONE)
	_ellipse(img, 10, 6, 1.3, 1.1, Color(1, 1, 0.95))         # reflet
	_rect(img, 9, 7, 2, 2, INK)                               # orbite G
	_rect(img, 13, 7, 2, 2, INK)                              # orbite D
	_px(img, 9, 7, CYAN)                                      # lueur dans l'orbite
	_px(img, 14, 7, CYAN)
	for tx in range(10, 15, 2):
		_px(img, tx, 10, INK)                                 # dents

func _fig_orc(img: Image) -> void:
	_ground_shadow(img)
	var skin := Color(0.30, 0.44, 0.30)        # olive sombre, distinct du gobelin vif
	var skin_l := skin.lightened(0.18)
	# Corps massif et large (la brute).
	_trapezoid_o(img, 11, 10, 21, 5.0, 7.5, skin.darkened(0.45))
	_trapezoid(img, 11, 11, 20, 4.0, 6.0, skin)
	_rect(img, 6, 12, 10, 2, Color(0.36, 0.25, 0.18))         # baudrier de cuir
	_rect(img, 8, 15, 6, 3, skin_l)                           # pectoraux éclairés
	# Tête lourde et carrée.
	_disc_o(img, 11, 7, 4.6, skin.darkened(0.4), INK)
	_disc(img, 11, 7, 3.8, skin)
	_ellipse(img, 9, 5, 1.6, 1.3, skin_l)
	_rect(img, 7, 6, 9, 1, INK)                               # arcade lourde
	_glow_eyes(img, 11, 7, BLOOD, 3)
	_tri_up(img, 9, 13, 1, 4, BONE)                           # grandes défenses
	_tri_up(img, 13, 13, 1, 4, BONE)
	_rect(img, 9, 11, 5, 1, INK)                              # bouche
	# Hache à lame nette (manche + tête trapue).
	_rect(img, 18, 5, 1, 15, Color(0.36, 0.25, 0.18))         # manche
	_rect(img, 14, 5, 5, 5, STEEL_D)                          # tête (contour)
	_rect(img, 15, 6, 3, 3, STEEL)
	_rect(img, 15, 6, 3, 1, STEEL_L)                          # tranchant éclairé
	_px(img, 14, 7, STEEL_L); _px(img, 14, 8, STEEL_L)        # biseau du fil

func _fig_spectre(img: Image) -> void:
	# Spectre : haut net, bas vaporeux et ondulé, semi-transparence.
	_disc_o(img, 12, 9, 5.0, ARCANE.darkened(0.35), INK_SOFT)
	_disc(img, 12, 9, 4.2, ARCANE.darkened(0.1))
	# Voile descendant ondulé.
	_trapezoid(img, 12, 11, 20, 3.5, 6.0, ARCANE.darkened(0.1))
	for x in range(6, 19):
		var cut := 20 - ((x % 3))           # bord déchiqueté
		for y in range(cut, TILE):
			_px(img, x, y, Color(0, 0, 0, 0))
	# Visage creux lumineux.
	_ellipse(img, 12, 9, 2.6, 2.2, Color(0.06, 0.05, 0.10))
	_glow_eyes(img, 12, 8, CYAN_L, 2)
	_px(img, 12, 11, CYAN)                  # bouche fantomatique
	_fade(img, 0.80)

func _fig_boss(img: Image) -> void:
	# Le Gardien : grande silhouette imposante, cornes, couronne de lueur.
	_ellipse(img, 12, 22, 8.0, 2.0, Color(INK.r, INK.g, INK.b, 0.35))   # ombre large
	# Manteau sombre teinté de sang.
	_trapezoid_o(img, 12, 9, 22, 4.5, 8.5, INK_SOFT)
	_trapezoid(img, 12, 10, 21, 3.6, 7.0, Color(0.22, 0.12, 0.16))
	_rect(img, 11, 13, 2, 8, BLOOD_D)                         # raie centrale
	# Pectoral / armure.
	_rect(img, 8, 13, 8, 3, Color(0.30, 0.16, 0.20))
	_disc_o(img, 12, 14, 2.0, GOLD, GOLD_D)                   # gemme de poitrine
	_px(img, 12, 13, GOLD_L)
	# Tête cornue.
	_disc_o(img, 12, 7, 4.6, INK_SOFT, INK)
	_disc(img, 12, 7, 3.8, Color(0.26, 0.16, 0.20))
	_tri_up(img, 6, 6, 2, 6, BONE_D)                          # corne G
	_tri_up(img, 18, 6, 2, 6, BONE_D)
	_px(img, 6, 0, BONE); _px(img, 18, 0, BONE)
	_glow_eyes(img, 12, 7, EMBER, 3)                          # regard de braise
	_px(img, 9, 7, GOLD_L); _px(img, 15, 7, GOLD_L)
	_rect(img, 10, 10, 5, 1, INK)                             # rictus

# --- Butin --------------------------------------------------------------------
func _gen_weapon() -> Image:
	var img := _new(false)
	# Épée droite, lame d'acier à arête, garde dorée.
	_rect(img, 10, 3, 4, 13, INK)                  # contour lame
	_rect(img, 11, 4, 2, 11, STEEL)
	_rect(img, 11, 4, 1, 11, STEEL_L)              # tranchant éclairé
	_tri_up(img, 12, 4, 1, 2, STEEL_L)             # pointe
	_rect(img, 7, 15, 10, 2, GOLD_D)               # garde (contour)
	_rect(img, 7, 15, 10, 1, GOLD)
	_px(img, 6, 15, GOLD); _px(img, 17, 15, GOLD)
	_rect(img, 11, 17, 2, 4, Color(0.40, 0.27, 0.18))   # poignée
	_disc_o(img, 12, 21, 1.6, GOLD, GOLD_D)        # pommeau
	_px(img, 12, 20, GOLD_L)
	return img

func _gen_armor() -> Image:
	var img := _new(false)
	# Bouclier héraldique en acier, umbo central + rivets.
	_trapezoid(img, 12, 3, 12, 7.0, 8.0, STEEL_D)  # haut (contour large)
	_trapezoid(img, 12, 4, 12, 6.0, 7.0, STEEL)
	for y in range(12, 22):
		var w := int(round(8.0 * (1.0 - float(y - 12) / 9.5)))
		_rect(img, 12 - w, y, 1, 1, STEEL_D)        # bords pointe (contour)
		_rect(img, 12 + w, y, 1, 1, STEEL_D)
		if w > 1:
			_rect(img, 12 - w + 1, y, (w - 1) * 2, 1, STEEL)
	_rect(img, 8, 5, 2, 8, STEEL_L)                 # reflet vertical
	_disc_o(img, 12, 10, 2.4, ARCANE, INK_SOFT)     # umbo arcanique
	_disc(img, 12, 10, 1.3, ARCANE_L)
	for ry in [5, 9, 13]:
		_px(img, 6, ry, STEEL_L)
		_px(img, 18, ry, STEEL_L)
	return img

func _gen_relic() -> Image:
	var img := _new(false)
	# Amulette : anneau d'or + gemme cyan rayonnante.
	_disc_o(img, 12, 15, 6.0, GOLD, GOLD_D)
	_disc(img, 12, 15, 3.0, Color(0, 0, 0, 0))      # évidement
	_px(img, 9, 12, GOLD_L)                          # reflet anneau
	_disc_o(img, 12, 6, 3.0, CYAN, INK_SOFT)         # gemme suspendue
	_disc(img, 12, 6, 1.7, CYAN_L)
	_px(img, 11, 5, Color(1, 1, 1))
	# Éclats de lumière.
	_px(img, 12, 2, CYAN_L); _px(img, 8, 6, CYAN_L); _px(img, 16, 6, CYAN_L)
	return img

func _gen_artifact() -> Image:
	var img := _new(false)
	# Étoile arcanique à 4 branches sur halo.
	_disc(img, 12, 12, 8.0, Color(ARCANE.r, ARCANE.g, ARCANE.b, 0.28))   # halo
	_disc(img, 12, 12, 5.0, Color(ARCANE.r, ARCANE.g, ARCANE.b, 0.30))
	for i in range(10):
		var w := int(round(3.5 * (1.0 - float(i) / 10.0)))
		_rect(img, 12 - w, 12 - i, w * 2 + 1, 1, ARCANE)       # haut
		_rect(img, 12 - w, 12 + i, w * 2 + 1, 1, ARCANE)       # bas
		_rect(img, 12 - i, 12 - w, 1, w * 2 + 1, ARCANE)       # gauche
		_rect(img, 12 + i, 12 - w, 1, w * 2 + 1, ARCANE)       # droite
	_disc(img, 12, 12, 2.4, ARCANE_L)                          # cœur
	_disc(img, 12, 12, 1.1, Color(1, 1, 1))
	return img

# --- Icônes de nœud de carte (palette "Les Strates", fond transparent) ---------
# Nœud COMBAT : deux épées croisées.
func _gen_node_combat() -> Image:
	var img := _new(false)
	# Lame A : poignée bas-gauche -> pointe haut-droite.
	_line(img, 5, 19, 18, 5, INK); _line(img, 6, 19, 19, 5, INK)
	_line(img, 5, 18, 17, 5, STEEL); _line(img, 6, 18, 18, 5, STEEL_L)
	_px(img, 19, 4, STEEL_L)                          # éclat de pointe
	# Lame B : poignée bas-droite -> pointe haut-gauche.
	_line(img, 19, 19, 6, 5, INK); _line(img, 18, 19, 5, 5, INK)
	_line(img, 19, 18, 7, 5, STEEL); _line(img, 18, 18, 6, 5, STEEL_L)
	_px(img, 4, 4, STEEL_L)
	# Gardes dorées + pommeaux (en bas, près des poignées).
	_line(img, 3, 17, 8, 20, GOLD); _line(img, 21, 17, 16, 20, GOLD)
	_disc_o(img, 5, 20, 1.4, GOLD, GOLD_D)
	_disc_o(img, 19, 20, 1.4, GOLD, GOLD_D)
	# Étincelle de choc au croisement.
	_px(img, 12, 12, Color(1, 1, 1)); _px(img, 12, 11, CYAN_L); _px(img, 13, 12, CYAN_L)
	return img

# Nœud GARDIEN (boss) : couronne cornue à gemme de braise.
func _gen_node_boss() -> Image:
	var img := _new(false)
	# Cornes d'os recourbées de part et d'autre.
	_line(img, 5, 14, 3, 7, BONE_D); _line(img, 6, 14, 4, 7, BONE)
	_px(img, 3, 6, BONE); _px(img, 4, 5, BONE)
	_line(img, 19, 14, 21, 7, BONE_D); _line(img, 18, 14, 20, 7, BONE)
	_px(img, 21, 6, BONE); _px(img, 20, 5, BONE)
	# Bandeau de couronne.
	_rect(img, 6, 14, 13, 5, GOLD_D)
	_rect(img, 6, 14, 13, 1, GOLD_L)
	_rect(img, 7, 15, 11, 3, GOLD)
	# Trois pointes de couronne.
	_tri_up(img, 8, 14, 2, 4, GOLD); _tri_up(img, 12, 14, 2, 6, GOLD); _tri_up(img, 16, 14, 2, 4, GOLD)
	_px(img, 8, 10, GOLD_L); _px(img, 16, 10, GOLD_L)
	# Gemme de braise au front + reflet.
	_diamond(img, 12, 8, 2, EMBER.darkened(0.2))
	_diamond(img, 12, 8, 1, EMBER)
	_px(img, 12, 7, GOLD_L)
	# Gemme centrale du bandeau.
	_diamond(img, 12, 16, 1, EMBER); _px(img, 12, 16, GOLD_L)
	return img

# Nœud ÉLITE : crâne cornu aux orbites de braise (combat renforcé).
func _gen_node_elite() -> Image:
	var img := _new(false)
	# Petites cornes.
	_tri_up(img, 6, 7, 1, 4, BONE_D); _tri_up(img, 18, 7, 1, 4, BONE_D)
	_px(img, 6, 3, BONE); _px(img, 18, 3, BONE)
	# Crâne.
	_disc_o(img, 12, 10, 6.0, BONE_D, INK)
	_disc(img, 12, 9, 5.2, BONE)
	_ellipse(img, 9, 6, 1.6, 1.3, Color(1, 1, 0.95))
	# Orbites + lueur de braise.
	_rect(img, 8, 8, 3, 3, INK); _rect(img, 14, 8, 3, 3, INK)
	_px(img, 9, 9, EMBER); _px(img, 15, 9, EMBER)
	_px(img, 9, 8, GOLD_L); _px(img, 15, 8, GOLD_L)
	_px(img, 12, 12, INK)                              # nasale
	# Mâchoire + dents.
	_rect(img, 8, 15, 9, 3, BONE_D); _rect(img, 8, 15, 9, 1, BONE)
	for tx in range(9, 17, 2):
		_rect(img, tx, 15, 1, 3, INK)
	return img

# Nœud BOUTIQUE : bourse de cuir, ficelle dorée, pièce qui dépasse.
func _gen_node_shop() -> Image:
	var img := _new(false)
	var leather := Color(0.45, 0.32, 0.22)
	var leather_d := leather.darkened(0.35)
	# Pièce d'or qui dépasse du col.
	_disc_o(img, 12, 6, 2.3, GOLD, GOLD_D); _px(img, 11, 5, GOLD_L)
	# Corps de la bourse.
	_disc_o(img, 12, 15, 7.0, leather_d, INK)
	_disc(img, 12, 15, 6.0, leather)
	_ellipse(img, 9, 12, 2.3, 1.6, leather.lightened(0.22))
	# Col plissé + ficelle.
	_rect(img, 8, 8, 8, 2, leather_d)
	_rect(img, 7, 10, 10, 1, GOLD_D); _rect(img, 7, 9, 10, 1, GOLD)
	# Marque d'or sur la bourse.
	_diamond(img, 12, 16, 2, GOLD); _px(img, 12, 16, GOLD_L)
	return img

# Nœud ÉVÉNEMENT : sigille arcanique avec point d'interrogation lumineux.
func _gen_node_event() -> Image:
	var img := _new(false)
	_disc(img, 12, 12, 8.0, Color(ARCANE.r, ARCANE.g, ARCANE.b, 0.25))   # halo
	_diamond(img, 12, 12, 7, ARCANE.darkened(0.35))
	_diamond(img, 12, 12, 6, ARCANE)
	_diamond(img, 12, 12, 4, ARCANE.darkened(0.45))
	# Point d'interrogation (cyan).
	_rect(img, 10, 8, 4, 1, CYAN_L)
	_px(img, 13, 9, CYAN_L); _px(img, 13, 10, CYAN_L)
	_px(img, 12, 11, CYAN_L); _px(img, 12, 12, CYAN_L)
	_px(img, 12, 13, CYAN_L)
	_px(img, 12, 15, Color(1, 1, 1))                  # point
	return img

# Nœud REPOS : feu de camp (bûches + flamme).
func _gen_node_rest() -> Image:
	var img := _new(false)
	var wood := Color(0.45, 0.32, 0.21)
	var wood_l := Color(0.55, 0.40, 0.27)
	# Bûches croisées.
	_line(img, 5, 19, 16, 15, INK); _line(img, 19, 19, 8, 15, INK)
	_line(img, 5, 18, 16, 14, wood); _line(img, 6, 18, 17, 14, wood_l)
	_line(img, 19, 18, 8, 14, wood); _line(img, 18, 18, 7, 14, wood_l)
	_px(img, 5, 18, wood_l); _px(img, 19, 18, wood_l)
	# Flamme.
	_tri_up(img, 12, 15, 4, 10, EMBER.darkened(0.25))
	_tri_up(img, 12, 15, 3, 8, EMBER)
	_tri_up(img, 12, 14, 2, 6, GOLD)
	_px(img, 12, 8, GOLD_L)
	_px(img, 10, 13, EMBER.lightened(0.1)); _px(img, 14, 13, EMBER)   # langues de feu
	# Braises au sol.
	_px(img, 9, 18, EMBER); _px(img, 15, 18, GOLD)
	return img

# --- Terrain par biome --------------------------------------------------------
func _gen_ground(a: Color, b: Color) -> Image:
	var img := _new(true)
	img.fill(a)
	for y in TILE:
		for x in TILE:
			var r := rng.randf()
			if r < 0.13:
				_px(img, x, y, a.darkened(0.16))
			elif r > 0.86:
				_px(img, x, y, b)
	# Liseré sombre discret (délimite la case sans bruit).
	for i in TILE:
		_px(img, i, TILE - 1, a.darkened(0.28))
		_px(img, TILE - 1, i, a.darkened(0.28))
		_px(img, i, 0, a.lightened(0.04))
	return img

func _gen_tree(trunk: Color, leaf: Color, style: String) -> Image:
	var img := _new(false)
	match style:
		"round":
			_rect(img, 11, 15, 2, 7, trunk.darkened(0.2))
			_rect(img, 11, 15, 1, 7, trunk)
			_disc_o(img, 12, 10, 7.0, leaf.darkened(0.35), INK_SOFT)
			_disc(img, 12, 10, 6.0, leaf)
			_disc(img, 9, 7, 2.4, leaf.lightened(0.25))      # masse éclairée
		"pine":
			_rect(img, 11, 18, 2, 4, trunk)
			_tri_up(img, 12, 19, 7, 8, leaf.darkened(0.35))
			_tri_up(img, 12, 19, 6, 7, leaf)
			_tri_up(img, 12, 14, 5, 6, leaf.darkened(0.15))
			_tri_up(img, 12, 10, 4, 5, leaf.lightened(0.15))
		"cactus":
			_rect(img, 10, 5, 4, 17, leaf.darkened(0.3))
			_rect(img, 11, 5, 3, 17, leaf)
			_rect(img, 11, 5, 1, 17, leaf.lightened(0.2))
			_rect(img, 6, 9, 2, 6, leaf); _rect(img, 6, 13, 3, 2, leaf)
			_rect(img, 16, 11, 2, 6, leaf); _rect(img, 15, 15, 3, 2, leaf)
			for yy in range(7, 21, 3):
				_px(img, 12, yy, leaf.lightened(0.35))
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
	_ellipse(img, 12, 15, 8.5, 6.5, INK_SOFT)        # contour
	_ellipse(img, 12, 15, 7.5, 5.5, c)
	_ellipse(img, 9, 12, 2.8, 2.0, c.lightened(0.30))   # facette éclairée
	_rect(img, 13, 11, 1, 8, c.darkened(0.4))        # fissure
	_rect(img, 13, 14, 4, 1, c.darkened(0.4))
	_rect(img, 6, 18, 11, 1, c.darkened(0.3))        # base ombrée
	return img

func _gen_water(c: Color) -> Image:
	var img := _new(true)
	img.fill(c.darkened(0.18))
	var hi := c.lightened(0.32)
	var mid := c.lightened(0.08)
	for y in range(1, TILE, 3):
		for x in TILE:
			var yy := y + ((x / 3) % 2)
			if yy < TILE:
				if (x + y) % 6 < 2:
					_px(img, x, yy, hi)
				elif (x + y) % 6 < 4:
					_px(img, x, yy, mid)
	return img

func _gen_decor(c: Color, style: String) -> Image:
	var img := _new(false)
	match style:
		"flower":
			_rect(img, 12, 14, 1, 6, POISON.darkened(0.2))
			_disc_o(img, 12, 12, 2.4, c, INK_SOFT)
			_px(img, 12, 12, GOLD_L)
		"mushroom":
			_rect(img, 12, 16, 2, 4, BONE)
			_ellipse(img, 13, 14, 4.2, 2.8, c.darkened(0.25))
			_ellipse(img, 13, 13, 3.4, 2.0, c)
			_px(img, 11, 13, Color(1, 1, 1)); _px(img, 14, 14, Color(1, 1, 1))
		"bones":
			_rect(img, 8, 16, 8, 1, BONE)
			_rect(img, 8, 15, 1, 3, BONE); _rect(img, 15, 15, 1, 3, BONE)
			_px(img, 7, 15, BONE_D); _px(img, 16, 15, BONE_D)
		"crystal":
			_diamond(img, 12, 14, 4, c.darkened(0.3))
			_diamond(img, 12, 14, 3, c)
			_rect(img, 12, 11, 1, 6, c.lightened(0.45))
			_px(img, 11, 12, Color(1, 1, 1))
		"reed":
			for sx in [9, 12, 15]:
				_rect(img, sx, 11, 1, 9, c.darkened(0.15))
				_ellipse(img, sx, 10, 1.4, 2.4, c.darkened(0.3))
		"ember":
			_ellipse(img, 12, 17, 3.4, 2.0, INK_SOFT)
			_ellipse(img, 12, 16, 2.4, 1.6, EMBER.darkened(0.2))
			_ellipse(img, 12, 16, 1.4, 1.0, EMBER)
			_px(img, 12, 14, GOLD_L)
		_:
			_disc_o(img, 12, 14, 2.0, c, INK_SOFT)
	return img

func _gen_road() -> Image:
	var img := _new(true)
	var dirt := Color(0.26, 0.22, 0.20)
	img.fill(dirt)
	for i in 60:
		var x := rng.randi_range(0, TILE - 1)
		var y := rng.randi_range(0, TILE - 1)
		_px(img, x, y, dirt.darkened(rng.randf() * 0.35))
	for i in 7:
		var x := rng.randi_range(2, TILE - 3)
		var y := rng.randi_range(2, TILE - 3)
		_ellipse(img, x, y, 1.4, 1.1, Color(0.40, 0.36, 0.33))   # pavés usés
		_px(img, x - 1, y - 1, Color(0.50, 0.46, 0.42))
	return img

func _gen_potion() -> Image:
	var img := _new(false)
	# Fiole arrondie, verre froid, liquide rouge, reflet net.
	_rect(img, 10, 3, 4, 2, Color(0.40, 0.28, 0.18))    # bouchon
	_rect(img, 10, 5, 4, 3, STEEL_D)                     # col
	_disc_o(img, 12, 15, 6.0, INK_SOFT, INK)             # contour corps
	_disc(img, 12, 15, 5.2, Color(0.55, 0.78, 0.88))     # verre
	_ellipse(img, 12, 17, 4.4, 3.6, BLOOD)               # liquide
	_ellipse(img, 12, 17, 3.4, 2.6, BLOOD.lightened(0.12))
	_rect(img, 9, 12, 1, 6, Color(1, 1, 1, 0.7))         # reflet
	_px(img, 14, 11, Color(1, 1, 1, 0.6))
	return img
