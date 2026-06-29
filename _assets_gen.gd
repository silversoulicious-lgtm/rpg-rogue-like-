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

	# --- Héroïne & classes (sprite "knight" = Aria) ---
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

# Héroïne Aria : silhouette élancée, armure d'acier, écharpe rouge, visière cyan.
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
	var fur := Color(0.42, 0.43, 0.50)
	# Corps quadrupède bas.
	_ellipse(img, 13, 15, 7.5, 4.2, fur.darkened(0.4))
	_ellipse(img, 13, 15, 6.5, 3.4, fur)
	_rect(img, 8, 18, 2, 3, fur.darkened(0.25))               # pattes
	_rect(img, 15, 18, 2, 3, fur.darkened(0.25))
	# Queue.
	_ellipse(img, 20, 13, 2.6, 1.5, fur.darkened(0.15))
	# Tête abaissée à gauche.
	_disc_o(img, 7, 12, 3.6, fur.darkened(0.35), INK)
	_disc(img, 7, 12, 2.9, fur)
	_tri_up(img, 5, 9, 1, 3, fur.darkened(0.2))               # oreilles
	_tri_up(img, 9, 9, 1, 3, fur.darkened(0.2))
	_rect(img, 2, 12, 3, 2, fur.lightened(0.12))              # museau
	_px(img, 2, 13, INK)                                      # truffe
	_rect(img, 6, 11, 2, 1, CYAN_L)                           # œil luisant

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
	var skin := Color(0.36, 0.52, 0.34)
	# Corps massif.
	_trapezoid_o(img, 12, 10, 21, 4.5, 7.0, skin.darkened(0.4))
	_trapezoid(img, 12, 11, 20, 3.6, 5.6, skin)
	_rect(img, 8, 12, 8, 2, Color(0.40, 0.28, 0.20))          # baudrier de cuir
	_rect(img, 9, 14, 6, 4, skin.lightened(0.10))             # pectoraux
	# Tête lourde.
	_disc_o(img, 12, 7, 4.4, skin.darkened(0.35), INK)
	_disc(img, 12, 7, 3.6, skin)
	_ellipse(img, 10, 5, 1.5, 1.2, skin.lightened(0.22))
	_rect(img, 8, 6, 9, 1, INK)                               # sourcil lourd
	_glow_eyes(img, 12, 7, BLOOD, 3)
	_tri_up(img, 10, 12, 1, 3, BONE)                          # défenses
	_tri_up(img, 14, 12, 1, 3, BONE)
	# Hache.
	_rect(img, 18, 6, 1, 13, Color(0.40, 0.28, 0.20))
	_tri_up(img, 19, 9, 3, 4, STEEL_L)

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
