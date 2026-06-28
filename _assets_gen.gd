extends SceneTree
# Générateur d'assets pixel-art : textures du monde + sprites.
# Lancé en headless : godot --headless --script res://_assets_gen.gd
# Produit des PNG 24x24 dans res://assets/.

const TILE := 24
var rng := RandomNumberGenerator.new()

func _init() -> void:
	rng.seed = 1337
	DirAccess.make_dir_recursive_absolute("res://assets")

	# --- Textures du monde ---
	_save(_gen_floor(), "floor")
	_save(_gen_wall(), "wall")
	_save(_gen_stairs(), "stairs")

	# --- Héros ---
	_save(_gen_creature(Color(0.86, 0.78, 0.45), "knight"), "knight")
	_save(_gen_creature(Color(0.45, 0.7, 1.0), "mage"), "mage")
	_save(_gen_creature(Color(0.45, 0.85, 0.5), "ranger"), "ranger")

	# --- Ennemis ---
	_save(_gen_creature(Color(0.45, 0.75, 0.3), "gobelin"), "gobelin")
	_save(_gen_creature(Color(0.7, 0.7, 0.72), "loup"), "loup")
	_save(_gen_creature(Color(0.92, 0.92, 0.86), "squelette"), "squelette")
	_save(_gen_creature(Color(0.35, 0.62, 0.35), "orc"), "orc")
	_save(_gen_creature(Color(0.68, 0.5, 0.95), "spectre"), "spectre")
	_save(_gen_creature(Color(0.85, 0.25, 0.25), "boss"), "boss")

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
		img.set_pixel(x, y, c)

func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_px(img, xx, yy, c)

func _ellipse(img: Image, cx: int, cy: int, rx: float, ry: float, c: Color) -> void:
	for yy in range(int(cy - ry), int(cy + ry) + 1):
		for xx in range(int(cx - rx), int(cx + rx) + 1):
			var dx := (xx - cx) / rx
			var dy := (yy - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				_px(img, xx, yy, c)

# Triangle plein, pointe vers le haut, base en bas.
func _tri_up(img: Image, cx: int, base_y: int, half_w: int, height: int, c: Color) -> void:
	for i in range(height):
		var w := int(round(half_w * (1.0 - float(i) / float(height))))
		var yy := base_y - i
		for xx in range(cx - w, cx + w + 1):
			_px(img, xx, yy, c)

# --- Textures du monde --------------------------------------------------------
func _gen_floor() -> Image:
	var img := _new(true)
	var base := Color(0.13, 0.12, 0.18)
	img.fill(base)
	for y in TILE:
		for x in TILE:
			var r := rng.randf()
			if r < 0.10:
				_px(img, x, y, base.darkened(0.18))
			elif r > 0.94:
				_px(img, x, y, base.lightened(0.10))
	# liseré sombre = délimite la dalle
	for i in TILE:
		_px(img, i, 0, base.darkened(0.35))
		_px(img, 0, i, base.darkened(0.35))
		_px(img, i, TILE - 1, base.darkened(0.45))
		_px(img, TILE - 1, i, base.darkened(0.45))
	return img

func _gen_wall() -> Image:
	var img := _new(true)
	var base := Color(0.27, 0.25, 0.38)
	img.fill(base)
	var mortar := base.darkened(0.5)
	var hi := base.lightened(0.2)
	var brick_h := 6
	var brick_w := 8
	var row := 0
	for by in range(0, TILE, brick_h):
		for x in TILE:
			_px(img, x, by, mortar)            # joint horizontal
			_px(img, x, by + 1, hi)            # reflet sous le joint
		var off := (brick_w / 2) if (row % 2 == 1) else 0
		var bx := -off
		while bx <= TILE:
			for yy in range(by, by + brick_h):
				_px(img, bx, yy, mortar)        # joint vertical
			bx += brick_w
		row += 1
	# grain
	for i in 40:
		var x := rng.randi_range(0, TILE - 1)
		var y := rng.randi_range(0, TILE - 1)
		_px(img, x, y, base.darkened(0.12))
	return img

func _gen_stairs() -> Image:
	var img := _new(false)                      # transparent : posé sur le sol
	var stone := Color(0.55, 0.5, 0.62)
	var dark := stone.darkened(0.4)
	# 4 marches montantes
	for s in range(4):
		var y := 18 - s * 4
		var w := 18 - s * 3
		var x := 3 + s * 1
		_rect(img, x, y, w, 4, stone)
		_rect(img, x, y, w, 1, stone.lightened(0.2))
		_rect(img, x, y + 3, w, 1, dark)
	# chevron doré "montée"
	var gold := Color(0.98, 0.85, 0.35)
	_tri_up(img, 12, 6, 4, 4, gold)
	return img

# --- Créatures (héros & ennemis) ---------------------------------------------
func _gen_creature(base: Color, kind: String) -> Image:
	var img := _new(false)
	var outline := base.darkened(0.55)
	var hi := base.lightened(0.3)
	var cx := 12
	var cy := 13
	var rx := 7.0
	var ry := 8.0
	if kind == "boss":
		rx = 8.5
		ry = 9.0
	# corps + contour
	_ellipse(img, cx, cy, rx + 1.0, ry + 1.0, outline)
	_ellipse(img, cx, cy, rx, ry, base)
	_ellipse(img, cx - 2, cy - 3, 2.2, 3.0, hi)   # reflet

	var white := Color(0.96, 0.97, 1.0)
	var pupil := Color(0.08, 0.08, 0.12)
	var ey := cy - 2

	match kind:
		"knight":
			# heaume : bandeau métallique + fentes lumineuses
			var metal := Color(0.78, 0.8, 0.85)
			_rect(img, cx - 6, cy - 5, 12, 2, metal.darkened(0.2))
			_rect(img, cx - 6, ey, 12, 3, metal.darkened(0.35))
			_rect(img, cx - 4, ey + 1, 2, 1, Color(0.5, 0.95, 1.0))
			_rect(img, cx + 2, ey + 1, 2, 1, Color(0.5, 0.95, 1.0))
			_tri_up(img, cx, cy - 6, 2, 4, Color(0.95, 0.3, 0.3))  # plumet
		"mage":
			# chapeau pointu + étoile
			_tri_up(img, cx, cy - 4, 7, 9, base.darkened(0.25))
			_px(img, cx, cy - 11, Color(1, 0.95, 0.5))
			_eyes(img, cx, ey, white, pupil)
		"ranger":
			# capuche
			_ellipse(img, cx, cy - 3, rx, 5.0, base.darkened(0.3))
			_ellipse(img, cx, cy - 1, rx - 1.0, 4.0, base.darkened(0.05))
			_eyes(img, cx, ey + 1, white, pupil)
		"gobelin":
			_tri_up(img, cx - 7, cy, 2, 5, base)     # oreille gauche
			_tri_up(img, cx + 7, cy, 2, 5, base)     # oreille droite
			_eyes(img, cx, ey, Color(1, 0.9, 0.4), pupil)
			_rect(img, cx - 3, cy + 4, 6, 1, outline)  # bouche
		"loup":
			_tri_up(img, cx - 4, cy - 6, 2, 4, base.darkened(0.1))  # oreilles
			_tri_up(img, cx + 4, cy - 6, 2, 4, base.darkened(0.1))
			_ellipse(img, cx, cy + 4, 4.0, 3.0, base.lightened(0.18))  # museau
			_px(img, cx, cy + 5, pupil)               # truffe
			_eyes(img, cx, ey, Color(1, 0.85, 0.4), pupil)
		"squelette":
			# crâne : grosses orbites + dents
			_rect(img, cx - 4, ey - 1, 3, 3, pupil)
			_rect(img, cx + 1, ey - 1, 3, 3, pupil)
			for tx in range(cx - 4, cx + 5, 2):
				_rect(img, tx, cy + 4, 1, 2, outline)
		"orc":
			_eyes(img, cx, ey, Color(1, 0.85, 0.4), pupil)
			_rect(img, cx - 5, ey - 2, 10, 1, outline)   # sourcil lourd
			_tri_up(img, cx - 3, cy + 6, 1, 3, white)     # défenses
			_tri_up(img, cx + 3, cy + 6, 1, 3, white)
		"spectre":
			_eyes(img, cx, ey, Color(0.8, 0.95, 1.0), Color(0.2, 0.4, 0.6))
			# bas ondulé + semi-transparence
			for x in TILE:
				for y in range(cy + 3, TILE):
					if (x / 2) % 2 == 0 and y > cy + 4:
						_px(img, x, y, Color(0, 0, 0, 0))
			_fade(img, 0.78)
		"boss":
			# cornes + regard menaçant
			_tri_up(img, cx - 6, cy - 6, 2, 5, base.darkened(0.3))
			_tri_up(img, cx + 6, cy - 6, 2, 5, base.darkened(0.3))
			_rect(img, cx - 5, ey, 4, 2, Color(1, 0.9, 0.3))
			_rect(img, cx + 1, ey, 4, 2, Color(1, 0.9, 0.3))
			_px(img, cx - 3, ey, pupil)
			_px(img, cx + 3, ey, pupil)
			_rect(img, cx - 3, cy + 5, 6, 1, pupil)
		_:
			_eyes(img, cx, ey, white, pupil)
	return img

func _eyes(img: Image, cx: int, ey: int, white: Color, pupil: Color) -> void:
	for s in [-3, 2]:
		_rect(img, cx + s, ey, 2, 2, white)
		_px(img, cx + s + 1, ey + 1, pupil)

func _fade(img: Image, a: float) -> void:
	for y in TILE:
		for x in TILE:
			var c := img.get_pixel(x, y)
			if c.a > 0.0:
				c.a *= a
				img.set_pixel(x, y, c)

# --- Butin --------------------------------------------------------------------
func _gen_weapon() -> Image:
	var img := _new(false)
	var blade := Color(0.82, 0.85, 0.9)
	var edge := blade.darkened(0.35)
	var gold := Color(0.9, 0.75, 0.3)
	var grip := Color(0.45, 0.3, 0.2)
	# lame
	_rect(img, 11, 4, 2, 11, blade)
	_px(img, 11, 4, edge)
	_tri_up(img, 12, 4, 1, 2, blade)
	# garde
	_rect(img, 8, 15, 8, 2, gold)
	# poignée + pommeau
	_rect(img, 11, 17, 2, 4, grip)
	_rect(img, 11, 21, 2, 1, gold)
	return img

func _gen_armor() -> Image:
	var img := _new(false)
	var steel := Color(0.55, 0.62, 0.78)
	var dark := steel.darkened(0.45)
	var hi := steel.lightened(0.28)
	# silhouette de bouclier héraldique (par lignes), contour puis remplissage
	for pass_i in range(2):
		var col := dark if pass_i == 0 else steel
		var inset := 0 if pass_i == 0 else 1
		for y in range(3 + inset, 22 - inset):
			var w: int
			if y == 3:
				w = 6
			elif y <= 13:
				w = 8
			else:
				w = int(round(8 * (1.0 - float(y - 13) / 8.0)))
			w -= inset
			if w > 0:
				_rect(img, 12 - w, y, w * 2, 1, col)
	# reflet vertical + umbo + rivets
	_rect(img, 9, 5, 2, 8, hi)
	_ellipse(img, 12, 10, 2.2, 2.2, dark)
	_ellipse(img, 12, 10, 1.3, 1.3, hi)
	for ry in [5, 9, 13]:
		_px(img, 6, ry, hi)
		_px(img, 17, ry, hi)
	return img

func _gen_relic() -> Image:
	var img := _new(false)
	var gold := Color(0.95, 0.8, 0.35)
	var golddk := gold.darkened(0.35)
	# anneau
	_ellipse(img, 12, 14, 6.0, 6.0, golddk)
	_ellipse(img, 12, 14, 5.0, 5.0, gold)
	_ellipse(img, 12, 14, 3.0, 3.0, Color(0, 0, 0, 0))
	# gemme
	var gem := Color(0.4, 0.85, 1.0)
	_ellipse(img, 12, 6, 2.5, 2.8, gem.darkened(0.3))
	_ellipse(img, 12, 6, 1.6, 1.9, gem)
	_px(img, 11, 5, Color(1, 1, 1))
	return img

func _gen_artifact() -> Image:
	var img := _new(false)
	var glow := Color(0.95, 0.6, 1.0, 0.35)
	var bright := Color(1.0, 0.85, 1.0)
	var core := Color(0.85, 0.4, 1.0)
	_ellipse(img, 12, 12, 7.0, 7.0, glow)       # halo
	# étoile à 4 branches
	_tri_up(img, 12, 12, 3, 9, core)            # haut
	_tri_up(img, 12, 12, 3, 9, core)
	for i in range(9):
		var w := int(round(3 * (1.0 - float(i) / 9.0)))
		_rect(img, 12 - w, 12 + i, w * 2, 1, core)   # bas
	for i in range(9):
		var h := int(round(3 * (1.0 - float(i) / 9.0)))
		_rect(img, 12 + i, 12 - h, 1, h * 2, core)   # droite
		_rect(img, 12 - i, 12 - h, 1, h * 2, core)   # gauche
	_ellipse(img, 12, 12, 2.0, 2.0, bright)     # cœur
	return img

# --- Terrain par biome --------------------------------------------------------
func _gen_ground(a: Color, b: Color) -> Image:
	var img := _new(true)
	img.fill(a)
	for y in TILE:
		for x in TILE:
			var r := rng.randf()
			if r < 0.14:
				_px(img, x, y, a.darkened(0.12))
			elif r > 0.84:
				_px(img, x, y, b)
	# liseré discret pour délimiter la case
	for i in TILE:
		_px(img, i, TILE - 1, a.darkened(0.18))
		_px(img, TILE - 1, i, a.darkened(0.18))
	return img

func _gen_tree(trunk: Color, leaf: Color, style: String) -> Image:
	var img := _new(false)
	match style:
		"round":
			_rect(img, 11, 15, 2, 7, trunk)
			_ellipse(img, 12, 10, 7.5, 7.5, leaf.darkened(0.3))
			_ellipse(img, 12, 10, 6.5, 6.5, leaf)
			_ellipse(img, 9, 7, 2.6, 2.4, leaf.lightened(0.22))
		"pine":
			_rect(img, 11, 18, 2, 4, trunk)
			_tri_up(img, 12, 18, 7, 7, leaf.darkened(0.25))
			_tri_up(img, 12, 13, 6, 6, leaf)
			_tri_up(img, 12, 9, 4, 5, leaf.lightened(0.14))
		"cactus":
			_rect(img, 11, 5, 3, 17, leaf)
			_rect(img, 6, 9, 2, 5, leaf)
			_rect(img, 6, 13, 3, 2, leaf)
			_rect(img, 16, 11, 2, 5, leaf)
			_rect(img, 14, 15, 3, 2, leaf)
			for yy in range(7, 21, 3):
				_px(img, 12, yy, leaf.lightened(0.35))
		"dead":
			_rect(img, 11, 6, 2, 16, trunk)
			_rect(img, 7, 11, 5, 1, trunk)
			_rect(img, 7, 8, 1, 4, trunk)
			_rect(img, 13, 13, 5, 1, trunk)
			_rect(img, 17, 9, 1, 5, trunk)
			_rect(img, 11, 5, 3, 2, trunk)
		_:
			_ellipse(img, 12, 12, 6.0, 6.0, leaf)
	return img

func _gen_rock(c: Color) -> Image:
	var img := _new(false)
	var dark := c.darkened(0.45)
	var hi := c.lightened(0.28)
	_ellipse(img, 12, 15, 8.5, 6.5, dark)
	_ellipse(img, 12, 15, 7.5, 5.5, c)
	_ellipse(img, 9, 12, 2.6, 1.9, hi)
	_rect(img, 12, 11, 1, 7, dark)       # fissure
	_rect(img, 12, 14, 4, 1, dark)
	return img

func _gen_water(c: Color) -> Image:
	var img := _new(true)
	img.fill(c.darkened(0.12))
	var hi := c.lightened(0.30)
	for y in range(1, TILE, 4):
		for x in TILE:
			var yy := y + ((x / 4) % 2)
			if yy < TILE and (x + y) % 5 < 2:
				_px(img, x, yy, hi)
	return img

func _gen_decor(c: Color, style: String) -> Image:
	var img := _new(false)
	match style:
		"flower":
			_rect(img, 12, 14, 1, 6, Color(0.30, 0.55, 0.25))
			_ellipse(img, 12, 12, 2.2, 2.2, c)
			_px(img, 12, 12, Color(1, 1, 0.85))
		"mushroom":
			_rect(img, 12, 16, 2, 4, Color(0.90, 0.88, 0.80))
			_ellipse(img, 13, 14, 4.0, 2.6, c)
			_px(img, 11, 13, Color(1, 1, 1))
			_px(img, 14, 14, Color(1, 1, 1))
		"bones":
			_rect(img, 8, 16, 8, 1, c)
			_rect(img, 8, 15, 1, 3, c)
			_rect(img, 15, 15, 1, 3, c)
		"crystal":
			_tri_up(img, 12, 19, 3, 9, c)
			_rect(img, 12, 12, 1, 6, c.lightened(0.4))
		"reed":
			for sx in [9, 12, 15]:
				_rect(img, sx, 11, 1, 9, c.darkened(0.12))
				_ellipse(img, sx, 10, 1.3, 2.2, c.darkened(0.3))
		"ember":
			_ellipse(img, 12, 16, 3.2, 2.2, c.darkened(0.35))
			_ellipse(img, 12, 15, 2.0, 1.5, c)
			_px(img, 12, 14, Color(1, 0.92, 0.55))
		_:
			_ellipse(img, 12, 14, 2.0, 2.0, c)
	return img

func _gen_road() -> Image:
	var img := _new(true)
	var dirt := Color(0.45, 0.38, 0.28)
	img.fill(dirt)
	for i in 60:
		var x := rng.randi_range(0, TILE - 1)
		var y := rng.randi_range(0, TILE - 1)
		_px(img, x, y, dirt.darkened(rng.randf() * 0.3))
	for i in 6:
		var x := rng.randi_range(2, TILE - 3)
		var y := rng.randi_range(2, TILE - 3)
		_ellipse(img, x, y, 1.5, 1.2, Color(0.60, 0.55, 0.50))
	return img

func _gen_potion() -> Image:
	var img := _new(false)
	var glass := Color(0.5, 0.85, 0.95)
	var liquid := Color(0.95, 0.3, 0.4)
	var cork := Color(0.55, 0.4, 0.25)
	# fiole : col étroit + corps arrondi
	_rect(img, 10, 4, 4, 4, glass.darkened(0.1))   # col
	_rect(img, 10, 3, 4, 2, cork)                   # bouchon
	_ellipse(img, 12, 15, 6.0, 6.5, glass.darkened(0.3))
	_ellipse(img, 12, 15, 5.0, 5.5, glass)
	# liquide (bas)
	_ellipse(img, 12, 17, 4.2, 3.8, liquid)
	# reflet
	_rect(img, 9, 12, 1, 5, Color(1, 1, 1, 0.7))
	return img
