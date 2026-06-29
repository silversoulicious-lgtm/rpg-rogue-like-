## Toute l'interface du jeu : sidebar permanente, journal, écran HUB (Pied de
## la Tour) et overlays (montée de niveau, inventaire).
## Lit l'état via une référence au jeu (game = Main) et appelle ses méthodes
## publiques sur les clics. Aucune logique de jeu ici : uniquement de l'affichage.
extends Node

const VIEW := Vector2(1280, 720)
const SIDEBAR_W := 384
const LOG_H := 150
const VERSION := "v0.5 — accès anticipé"

# Pitch court par type d'arme, affiché sur la fiche de loadout.
const WEAPON_PITCH := {
	"melee": "Corps-à-corps · zone & encaisse",
	"ranged": "À distance · rapide & perçant",
	"magic": "Magie · effets & portée",
}

const STAT_ROWS := [
	["atk", "Attaque"], ["magic", "Magie"], ["defense", "Défense"],
	["speed", "Vitesse"], ["hp_regen", "Régén PV/tour"], ["vision", "Vision"],
	["crit", "Critique"], ["dodge", "Esquive"], ["lifesteal", "Vol de vie"],
	["run_shards", "Éclats (run)"], ["bank", "Banque"],
]

var game                          # référence vers Main

# Noeuds
var hud_layer: CanvasLayer
var menu_layer: CanvasLayer
var menu_bg: TextureRect
var menu_root: Control
var overlay_layer: CanvasLayer
var overlay_content: VBoxContainer
var log_label: RichTextLabel
# Sidebar
var sb_floor: Label
var sb_hero: Label
var sb_level: Label
var sb_ability: Label
var hp_bar: ProgressBar
var hp_text: Label
var xp_bar: ProgressBar
var stat_labels: Dictionary = {}
var equip_box: VBoxContainer
var artifact_box: VBoxContainer
var power_box: VBoxContainer
var synergy_box: VBoxContainer
var status_box: VBoxContainer

var map_layer: CanvasLayer
var map_root: Control

const NODE_LABELS := {
	"combat": "⚔ Combat", "elite": "☠ Élite", "shop": "🏪 Boutique",
	"event": "❔ Événement", "rest": "❤ Repos", "boss": "👑 GARDIEN",
}
const NODE_COLORS := {
	"combat": Color(0.85, 0.85, 0.9), "elite": Color(1.0, 0.6, 0.4),
	"shop": Color(0.5, 1.0, 0.8), "event": Color(0.7, 0.8, 1.0),
	"rest": Color(0.5, 0.95, 0.5), "boss": Color(1.0, 0.35, 0.35),
}

func setup(game_ref) -> void:
	game = game_ref
	_build_hud()
	_build_menu()
	_build_overlay()
	_build_map()

func play_area() -> Vector2:
	return Vector2(VIEW.x - SIDEBAR_W, VIEW.y - LOG_H)

# --- Construction -------------------------------------------------------------
func _build_hud() -> void:
	hud_layer = CanvasLayer.new()
	add_child(hud_layer)
	_build_sidebar()
	_build_log()

func _build_sidebar() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(VIEW.x - SIDEBAR_W, 0)
	panel.size = Vector2(SIDEBAR_W, VIEW.y)
	panel.add_theme_stylebox_override("panel", Ui.panel_style(Color(0.09, 0.08, 0.13)))
	hud_layer.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var v := Ui.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.custom_minimum_size = Vector2(SIDEBAR_W - 56, 0)
	scroll.add_child(v)

	v.add_child(Ui.label("⛫ LES STRATES", 20, Color(0.72, 0.62, 1.0)))
	sb_floor = Ui.label("", 16, Color(1.0, 0.85, 0.35)); v.add_child(sb_floor)
	sb_hero = Ui.label("", 18); v.add_child(sb_hero)
	hp_text = Ui.label("", 14); v.add_child(hp_text)
	hp_bar = Ui.progress_bar(18, Color(0.3, 0.8, 0.35), Color(0.25, 0.07, 0.07)); v.add_child(hp_bar)
	sb_level = Ui.label("", 14, Color(0.7, 0.95, 0.7)); v.add_child(sb_level)
	xp_bar = Ui.progress_bar(8, Color(0.55, 0.85, 0.4), Color(0.12, 0.15, 0.1), 3); v.add_child(xp_bar)

	v.add_child(_section("STATISTIQUES"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	for pair in STAT_ROWS:
		grid.add_child(Ui.label(pair[1], 14, Color(0.7, 0.7, 0.78)))
		var val := Ui.label("", 14)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(val)
		stat_labels[pair[0]] = val

	v.add_child(_section("CAPACITÉ"))
	sb_ability = Ui.label("", 14, Color.WHITE, false, true, SIDEBAR_W - 56); v.add_child(sb_ability)
	v.add_child(_section("ÉTATS"))
	status_box = Ui.vbox(3); v.add_child(status_box)
	v.add_child(_section("ÉQUIPEMENT"))
	equip_box = Ui.vbox(6); v.add_child(equip_box)
	v.add_child(_section("ARTEFACTS"))
	artifact_box = Ui.vbox(6); v.add_child(artifact_box)
	v.add_child(_section("POUVOIRS"))
	power_box = Ui.vbox(6); v.add_child(power_box)
	v.add_child(_section("SYNERGIES"))
	synergy_box = Ui.vbox(4); v.add_child(synergy_box)
	v.add_child(Ui.label("[I] Inventaire", 13, Color(0.6, 0.85, 1.0)))

func _section(txt: String) -> Label:
	return Ui.label("— %s —" % txt, 13, Color(0.55, 0.8, 1.0))

func _build_log() -> void:
	var play_w := VIEW.x - SIDEBAR_W
	var panel := PanelContainer.new()
	panel.position = Vector2(12, VIEW.y - LOG_H)
	panel.size = Vector2(play_w - 24, LOG_H - 10)
	panel.add_theme_stylebox_override("panel", Ui.panel_style(Color(0.08, 0.07, 0.11)))
	hud_layer.add_child(panel)

	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.fit_content = true
	log_label.scroll_active = false
	log_label.custom_minimum_size = Vector2(play_w - 48, LOG_H - 32)
	panel.add_child(log_label)

func _build_menu() -> void:
	menu_layer = CanvasLayer.new()
	menu_layer.layer = 2
	add_child(menu_layer)
	menu_bg = Ui.gradient_bg(Color(0.11, 0.08, 0.17), Color(0.02, 0.02, 0.05))
	menu_layer.add_child(menu_bg)
	menu_root = Control.new()
	menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(menu_root)

## Vide le contenu du calque menu (les écrans se reconstruisent à chaque appel).
func _menu_clear() -> void:
	for c in menu_root.get_children():
		menu_root.remove_child(c)
		c.queue_free()

## Colonne centrée pour un écran de menu. `scroll` enveloppe dans un défilement
## vertical (écrans longs : sanctuaire, fin de run) ; sinon centrage parfait.
func _menu_column(width: float = 720.0, scroll: bool = true) -> VBoxContainer:
	_menu_clear()
	var col := Ui.vbox(10)
	col.custom_minimum_size = Vector2(width, 0)
	if scroll:
		var sc := ScrollContainer.new()
		sc.set_anchors_preset(Control.PRESET_FULL_RECT)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		menu_root.add_child(sc)
		var m := MarginContainer.new()
		m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var side: int = int(max(40.0, (VIEW.x - width) / 2.0))
		m.add_theme_constant_override("margin_left", side)
		m.add_theme_constant_override("margin_right", side)
		m.add_theme_constant_override("margin_top", 36)
		m.add_theme_constant_override("margin_bottom", 36)
		sc.add_child(m)
		m.add_child(col)
	else:
		var cc := CenterContainer.new()
		cc.set_anchors_preset(Control.PRESET_FULL_RECT)
		menu_root.add_child(cc)
		cc.add_child(col)
	return col

func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _menu_show() -> void:
	menu_layer.visible = true
	hud_layer.visible = false
	overlay_layer.visible = false
	map_layer.visible = false

func _build_overlay() -> void:
	overlay_layer = CanvasLayer.new()
	overlay_layer.layer = 3
	overlay_layer.visible = false
	add_child(overlay_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.03, 0.07, 0.93)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_layer.add_child(dim)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	overlay_layer.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 80)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	scroll.add_child(margin)
	overlay_content = Ui.vbox(8)
	overlay_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(overlay_content)

# --- Bascule d'écrans ---------------------------------------------------------
func show_game() -> void:
	menu_layer.visible = false
	hud_layer.visible = true

func hide_overlay() -> void:
	overlay_layer.visible = false

# --- Carte de strate ----------------------------------------------------------
func _build_map() -> void:
	map_layer = CanvasLayer.new()
	map_layer.layer = 2
	map_layer.visible = false
	add_child(map_layer)
	map_root = Control.new()
	map_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_layer.add_child(map_root)

func hide_map() -> void:
	map_layer.visible = false

func show_map(run_map, pos: Vector2i) -> void:
	hud_layer.visible = true
	menu_layer.visible = false
	overlay_layer.visible = false
	map_layer.visible = true
	for c in map_root.get_children():
		map_root.remove_child(c)
		c.queue_free()

	var w: float = VIEW.x - SIDEBAR_W
	var h: float = VIEW.y
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.09)
	bg.size = Vector2(w, h)
	map_root.add_child(bg)
	var title := Ui.label("STRATE %d — choisis ta voie" % (game.map_act + 1), 20, Color(0.72, 0.62, 1.0))
	title.position = Vector2(24, 16)
	map_root.add_child(title)

	# positions par rangée (rangée 0 en bas, boss en haut)
	var margin_x := 80.0
	var top := 70.0
	var bottom := 56.0
	var rows: int = run_map.nodes.size()
	var span: float = (h - top - bottom) / float(max(1, rows - 1))
	var positions: Array = []
	for r in rows:
		var rowpos: Array = []
		var y: float = h - bottom - float(r) * span
		for node in run_map.nodes[r]:
			rowpos.append(Vector2(margin_x + node["x_frac"] * (w - 2.0 * margin_x), y))
		positions.append(rowpos)

	# liens
	for r in rows - 1:
		for ni in run_map.nodes[r].size():
			for j in run_map.nodes[r][ni]["edges"]:
				var line := Line2D.new()
				line.width = 3.0
				line.default_color = Color(0.28, 0.27, 0.42)
				line.points = [positions[r][ni], positions[r + 1][j]]
				map_root.add_child(line)

	# nœuds
	var reach: Array = game.reachable_indices()
	var next_row: int = pos.x + 1
	for r in rows:
		for ni in run_map.nodes[r].size():
			var node: Dictionary = run_map.nodes[r][ni]
			var btn := Ui.button(NODE_LABELS.get(node["type"], "?"))
			btn.size = Vector2(130, 40)
			btn.position = positions[r][ni] - Vector2(65, 20)
			btn.add_theme_color_override("font_color", NODE_COLORS.get(node["type"], Color.WHITE))
			var is_reachable: bool = (r == next_row and reach.has(ni))
			btn.disabled = not is_reachable
			if r == pos.x and ni == pos.y:
				btn.add_theme_color_override("font_color", Color(1, 1, 0.5))
			if is_reachable:
				btn.pressed.connect(game.choose_map_node.bind(ni))
			map_root.add_child(btn)

# --- Overlays boutique / événement / repos ------------------------------------
func show_shop(stock: Array, shards: int) -> void:
	map_layer.visible = false
	overlay_layer.visible = true
	_overlay_clear()
	_overlay_title("🏪 BOUTIQUE — Éclats : %d" % shards, Color(1.0, 0.85, 0.4))
	for item in stock:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var txt: String
		var col: Color
		if item.get("kind", "") == "equip":
			txt = "%s [%s]  (%s)" % [item["name"], item.get("rarity_name", ""), Data.bonus_summary(item["bonus"])]
			col = item.get("rarity_color", Color.WHITE)
		elif item.get("kind", "") == "power":
			txt = "Ω %s  (pouvoir)" % item["name"]
			col = item.get("color", Color.WHITE)
		else:
			txt = "%s  (consommable)" % item["name"]
			col = item.get("color", Color.WHITE)
		var lbl := Ui.label(txt, 15, col)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var price: int = int(item.get("price", 0))
		var b := Ui.button("Acheter (%d é)" % price)
		b.disabled = shards < price
		b.pressed.connect(game.buy_shop_item.bind(item))
		row.add_child(b)
		overlay_content.add_child(row)
		if item.get("desc", "") != "":
			overlay_content.add_child(Ui.label("   ✦ " + item["desc"], 12, Color(0.85, 0.7, 0.35), false, true, 700))
	overlay_content.add_child(HSeparator.new())
	var heal := Ui.button("Soin +50% PV   (15 é)", 40)
	heal.disabled = shards < 15
	heal.pressed.connect(game.buy_shop_heal)
	overlay_content.add_child(heal)
	var leave := Ui.button("Quitter la boutique", 42)
	leave.pressed.connect(game.leave_shop)
	overlay_content.add_child(leave)

func show_event(event: Dictionary) -> void:
	map_layer.visible = false
	overlay_layer.visible = true
	_overlay_clear()
	_overlay_title("❔ %s" % event["title"], Color(0.7, 0.85, 1.0))
	_overlay_label(event["desc"], Color(0.75, 0.75, 0.82))
	overlay_content.add_child(HSeparator.new())
	for i in event["choices"].size():
		var btn := Ui.button(event["choices"][i]["label"], 46, 17)
		btn.pressed.connect(game.resolve_event.bind(i))
		overlay_content.add_child(btn)

func show_rest() -> void:
	map_layer.visible = false
	overlay_layer.visible = true
	_overlay_clear()
	_overlay_title("❤ FEU DE CAMP", Color(0.6, 0.95, 0.6))
	_overlay_label("Un moment de répit avant de poursuivre l'ascension.", Color(0.75, 0.75, 0.82))
	overlay_content.add_child(HSeparator.new())
	var b1 := Ui.button("Se reposer   (+40% PV)", 46, 17)
	b1.pressed.connect(game.rest_choice.bind("heal"))
	overlay_content.add_child(b1)
	var b2 := Ui.button("S'entraîner   (+3 ATK ce run)", 46, 17)
	b2.pressed.connect(game.rest_choice.bind("train"))
	overlay_content.add_child(b2)

# --- Écran-titre --------------------------------------------------------------
func show_title() -> void:
	_menu_show()
	var col := _menu_column(560.0, false)
	col.add_theme_constant_override("separation", 6)
	col.add_child(Ui.label("⛫", 72, Ui.ACCENT_SOFT, true))
	col.add_child(Ui.label("L E S   S T R A T E S", 46, Ui.ACCENT_SOFT, true))
	col.add_child(Ui.label("Roguelike d'ascension — grimpe la tour, strate par strate.", 15, Ui.MUTED, true))
	col.add_child(_spacer(26))

	var play := Ui.menu_button("▶   Nouvelle Ascension", 360.0)
	play.pressed.connect(game.open_loadout)
	col.add_child(play)
	var sanct := Ui.menu_button("✦   Sanctuaire  (%d Éclats)" % GameState.shards, 360.0)
	sanct.pressed.connect(game.open_meta)
	col.add_child(sanct)
	var know := Ui.menu_button("✶   Arbre de Connaissances  (%d)" % GameState.knowledge, 360.0)
	know.pressed.connect(game.open_knowledge)
	col.add_child(know)
	var opt := Ui.menu_button("⚙   Options", 360.0)
	opt.pressed.connect(show_options)
	col.add_child(opt)
	var quit := Ui.menu_button("✕   Quitter", 360.0)
	quit.pressed.connect(game.quit_game)
	col.add_child(quit)

	col.add_child(_spacer(22))
	if GameState.best_floor > 1:
		col.add_child(Ui.label("Record d'ascension : Strate atteinte à l'Étage %d" % GameState.best_floor, 13, Ui.GOLD, true))
	col.add_child(Ui.label(VERSION, 12, Color(0.45, 0.45, 0.55), true))

# --- Loadout : choix de l'arme de départ (fiches détaillées) ------------------
func show_loadout() -> void:
	_menu_show()
	var col := _menu_column(1180.0, false)
	col.add_child(Ui.label("CHOISIS TON ARME", 30, Ui.ACCENT_SOFT, true))
	col.add_child(Ui.label("%s aborde la Tour selon l'arme qu'elle empoigne. Tu en trouveras d'autres en chemin." % Data.HEROINE["name"], 14, Ui.MUTED, true))
	col.add_child(_spacer(10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	for wtype in Data.WEAPON_TYPES:
		row.add_child(_weapon_card(wtype))
	if GameState.oaths_unlocked():
		col.add_child(_spacer(10))
		_build_oaths_panel(col)
	col.add_child(_spacer(14))
	var back := Ui.menu_button("↩   Retour", 240.0, 16)
	back.pressed.connect(game.return_to_title)
	col.add_child(back)

## Serments : modificateurs de difficulté optionnels (toggles) avant de choisir l'arme.
func _build_oaths_panel(col: VBoxContainer) -> void:
	col.add_child(Ui.label("⚔  SERMENTS — opte pour plus de difficulté contre de meilleures récompenses", 16, Color(0.9, 0.55, 0.55), true))
	for o in Data.OATHS:
		if o.get("major", false) and not GameState.major_oaths_unlocked():
			continue
		var on: bool = game.has_oath(o["id"])
		var mark: String = "[✓] " if on else "[  ] "
		var btn := Ui.button("%s%s — %s" % [mark, o["name"], o["desc"]], 46, 14)
		btn.add_theme_color_override("font_color", Color(0.95, 0.7, 0.7) if on else Color(0.7, 0.7, 0.78))
		btn.pressed.connect(game.toggle_oath.bind(o["id"]))
		col.add_child(btn)

func _weapon_card(wtype: String) -> Control:
	var h: Dictionary = Data.HEROINE
	var wpn: Dictionary = Data.make_starter_weapon(wtype)
	var b: Dictionary = wpn["bonus"]
	var col_w: Color = Data.WEAPON_TYPE_COLOR[wtype]
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Ui.card_style(Color(0.12, 0.10, 0.17), col_w.darkened(0.1)))
	var v := Ui.vbox(7)
	v.custom_minimum_size = Vector2(336, 0)
	panel.add_child(v)

	var portrait := _sprite_portrait("arme", col_w)
	if portrait != null:
		v.add_child(portrait)
	v.add_child(Ui.label(Data.WEAPON_TYPE_NAME[wtype], 26, col_w, true))
	v.add_child(Ui.label(wpn["name"], 14, Ui.GOLD, true))
	v.add_child(Ui.label(WEAPON_PITCH.get(wtype, ""), 12, Ui.MUTED, true))
	v.add_child(HSeparator.new())

	var hp: int = int(h["max_hp"]) + GameState.bonus_hp() + int(b.get("max_hp", 0))
	var atk: int = int(h["atk"]) + GameState.bonus_atk() + int(b.get("atk", 0))
	var magic: int = int(h["magic"]) + int(b.get("magic", 0))
	var defense: int = int(h["defense"]) + int(b.get("defense", 0))
	var speed: int = int(h["speed"]) + int(b.get("speed", 0))
	v.add_child(Ui.stat_gauge("PV", hp, 60, Color(0.3, 0.8, 0.35), 150))
	v.add_child(Ui.stat_gauge("ATK", atk, 14, Color(0.9, 0.55, 0.35), 150))
	v.add_child(Ui.stat_gauge("MAG", magic, 12, Color(0.45, 0.7, 1.0), 150))
	v.add_child(Ui.stat_gauge("DÉF", defense, 8, Color(0.7, 0.7, 0.78), 150))
	v.add_child(Ui.stat_gauge("VIT", speed, 130, Color(0.6, 0.95, 0.6), 150))
	v.add_child(HSeparator.new())

	var sk: Dictionary = Data.SKILLS[Data.WEAPON_TYPE_BASE_SKILL[wtype]]
	v.add_child(Ui.label("✦ Active — " + sk["name"], 15, Ui.ACCENT_SOFT, true))
	v.add_child(Ui.label("%s  (recharge %d tours)" % [sk["desc"], int(sk["cd"])], 12, Ui.MUTED, true, true, 300))
	v.add_child(Ui.label("⚙ Passive", 14, Color(0.85, 0.7, 0.35), true))
	v.add_child(Ui.label(wpn["desc"], 12, Ui.MUTED, true, true, 300))
	v.add_child(_spacer(6))
	var choose := Ui.menu_button("Choisir", 300.0, 17)
	choose.pressed.connect(game.choose_loadout.bind(wtype))
	v.add_child(choose)
	return panel

## Portrait pixel-art d'un sprite (agrandi, filtre voisin, teinté).
func _sprite_portrait(sprite: String, tint: Color) -> Control:
	var path := "res://assets/%s.png" % sprite
	if not ResourceLoader.exists(path):
		return null
	var tex = load(path)
	var holder := CenterContainer.new()
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", Ui.card_style(Color(0.08, 0.07, 0.11), tint.darkened(0.3), 8))
	var tr := TextureRect.new()
	tr.texture = tex
	tr.custom_minimum_size = Vector2(72, 72)
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.modulate = tint
	frame.add_child(tr)
	holder.add_child(frame)
	return holder

# --- Sanctuaire (méta-progression entre les runs) -----------------------------
func show_meta() -> void:
	_menu_show()
	var col := _menu_column(680.0, true)
	col.add_child(Ui.label("✦  SANCTUAIRE", 32, Ui.ACCENT_SOFT, true))
	col.add_child(Ui.label("Au pied de la Tour, dépense tes Éclats en bénédictions permanentes.", 14, Ui.MUTED, true))
	col.add_child(_spacer(6))
	col.add_child(Ui.label("Éclats en banque : %d        Record : Étage %d" % [GameState.shards, GameState.best_floor], 18, Ui.GOLD, true))
	col.add_child(HSeparator.new())

	for key in Data.UPGRADE_ORDER:
		var lvl: int = GameState.upgrade_level(key)
		var info: Dictionary = Data.UPGRADES[key]
		var label_txt: String
		if GameState.is_maxed(key):
			label_txt = "%s  (niv. %d)  —  %s     ★ MAX" % [info["name"], lvl, info["desc"]]
		else:
			label_txt = "%s  (niv. %d)  —  %s     [%d Éclats]" % [info["name"], lvl, info["desc"], Data.upgrade_cost(key, lvl)]
		var btn := Ui.button(label_txt, 46, 15)
		btn.disabled = not GameState.can_afford(key)
		btn.pressed.connect(_on_buy.bind(key))
		col.add_child(btn)

	col.add_child(HSeparator.new())
	var play := Ui.menu_button("▶   Choisir un héros", 360.0)
	play.pressed.connect(game.open_loadout)
	col.add_child(play)
	var back := Ui.menu_button("↩   Menu principal", 360.0, 16)
	back.pressed.connect(game.return_to_title)
	col.add_child(back)

func _on_buy(key: String) -> void:
	if GameState.buy_upgrade(key):
		show_meta()

# --- Arbre de Connaissances ---------------------------------------------------
func show_knowledge() -> void:
	_menu_show()
	var col := _menu_column(820.0, true)
	col.add_child(Ui.label("✶  ARBRE DE CONNAISSANCES", 30, Color(0.7, 0.85, 1.0), true))
	col.add_child(Ui.label("Les Connaissances ne s'achètent pas en force brute : elles débloquent des systèmes qui changent ta façon de jouer.", 14, Ui.MUTED, true, true, 760))
	col.add_child(_spacer(4))
	col.add_child(Ui.label("Connaissances : %d   —   gagnées en repoussant ton record et en terrassant les Gardiens." % GameState.knowledge, 17, Color(0.7, 0.85, 1.0), true))
	col.add_child(HSeparator.new())

	for bkey in Data.KNOWLEDGE_BRANCHES:
		var binfo: Dictionary = Data.KNOWLEDGE_BRANCHES[bkey]
		col.add_child(Ui.label("◈ " + str(binfo["name"]), 19, binfo.get("color", Color.WHITE), true))
		for nid in Data.KNOWLEDGE_ORDER:
			var node: Dictionary = Data.KNOWLEDGE_NODES[nid]
			if String(node["branch"]) != bkey:
				continue
			col.add_child(_knowledge_row(nid, node))
		col.add_child(_spacer(6))

	col.add_child(HSeparator.new())
	var back := Ui.menu_button("↩   Menu principal", 360.0, 16)
	back.pressed.connect(game.return_to_title)
	col.add_child(back)

func _knowledge_row(nid: String, node: Dictionary) -> Control:
	var owned: bool = GameState.has_knowledge_node(nid)
	var prereq_ok: bool = GameState.node_prereqs_met(nid)
	var label_txt: String
	if owned:
		label_txt = "✔ %s  —  %s     ★ DÉBLOQUÉ" % [node["name"], node["desc"]]
	elif not prereq_ok:
		var reqs: Array = []
		for r in node["requires"]:
			reqs.append(str(Data.KNOWLEDGE_NODES[r]["name"]))
		label_txt = "🔒 %s  —  %s     (requiert : %s)" % [node["name"], node["desc"], ", ".join(reqs)]
	else:
		label_txt = "%s  —  %s     [%d Connaissance(s)]" % [node["name"], node["desc"], int(node["cost"])]
	var btn := Ui.button(label_txt, 52, 14)
	btn.disabled = owned or not GameState.can_unlock_node(nid)
	btn.pressed.connect(_on_buy_knowledge.bind(nid))
	return btn

func _on_buy_knowledge(nid: String) -> void:
	if GameState.buy_knowledge_node(nid):
		show_knowledge()

# --- Écran de fin de run (mort) -----------------------------------------------
func show_gameover(death_summary: String) -> void:
	_menu_show()
	var col := _menu_column(680.0, true)
	col.add_child(Ui.label("💀  FIN DE L'ASCENSION", 30, Color(1.0, 0.5, 0.45), true))
	if death_summary != "":
		col.add_child(Ui.label(death_summary, 17, Color(1.0, 0.7, 0.6), true, true))
	col.add_child(_spacer(6))
	_build_run_journal(col)
	col.add_child(HSeparator.new())
	col.add_child(Ui.label("Tes Éclats ont rejoint la banque du Sanctuaire.", 14, Ui.GOLD, true))
	col.add_child(_spacer(6))

	var sanct := Ui.menu_button("✦   Améliorer au Sanctuaire", 360.0)
	sanct.pressed.connect(game.open_meta)
	col.add_child(sanct)
	var again := Ui.menu_button("▶   Nouvelle Ascension", 360.0)
	again.pressed.connect(game.open_loadout)
	col.add_child(again)
	var title := Ui.menu_button("↩   Menu principal", 360.0, 16)
	title.pressed.connect(game.return_to_title)
	col.add_child(title)

## Journal récapitulatif du dernier run, ajouté à la colonne `col` fournie.
func _build_run_journal(col: VBoxContainer) -> void:
	var r: Dictionary = GameState.last_run
	if r.is_empty():
		return
	col.add_child(Ui.label("— Journal du run —", 16, Color(0.6, 0.85, 1.0), true))
	col.add_child(Ui.label("Étage atteint : %d        Niveau : %d" % [int(r.get("floor", 1)), int(r.get("level", 1))], 15, Color(0.85, 0.85, 0.92), true))
	col.add_child(Ui.label("Ennemis vaincus : %d        Meilleur coup : %d" % [int(r.get("kills", 0)), int(r.get("best_hit", 0))], 15, Color(0.85, 0.85, 0.92), true))
	col.add_child(Ui.label("Éclats du run : %d   (banque : %d)" % [int(r.get("shards", 0)), GameState.shards], 15, Color(1.0, 0.85, 0.35), true))
	var item_name: String = str(r.get("item", ""))
	if item_name != "":
		col.add_child(Ui.label("Objet le plus marquant : %s" % item_name, 15, Color.html(str(r.get("item_color", "d2d2e0"))), true))
	col.add_child(Ui.label("Records — Étage %d · %d ennemis vaincus" % [GameState.best_floor, GameState.best_kills], 14, Color(0.7, 0.95, 0.7), true))

# --- Options (overlay au-dessus du menu) --------------------------------------
func show_options() -> void:
	overlay_layer.visible = true
	_overlay_clear()
	_overlay_title("⚙  OPTIONS", Ui.ACCENT_SOFT)
	var fs := Ui.button(_fullscreen_label(), 46, 17)
	fs.pressed.connect(_toggle_fullscreen)
	overlay_content.add_child(fs)
	overlay_content.add_child(Ui.label("Volume musique / effets — à venir dans une prochaine mise à jour.", 13, Ui.MUTED))
	overlay_content.add_child(HSeparator.new())
	overlay_content.add_child(Ui.label("Commandes", 16, Color(0.6, 0.85, 1.0)))
	overlay_content.add_child(Ui.label("Déplacer : WASD / flèches / HJKL    Capacité : ESPACE", 13, Ui.MUTED))
	overlay_content.add_child(Ui.label("Attendre : .    Inventaire : I    Retour menu : Échap", 13, Ui.MUTED))
	overlay_content.add_child(HSeparator.new())
	var back := Ui.button("Retour", 44, 16)
	back.pressed.connect(hide_overlay)
	overlay_content.add_child(back)

func _fullscreen_label() -> String:
	var mode := DisplayServer.window_get_mode()
	var on: bool = mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	return "Plein écran : %s" % ("ACTIVÉ" if on else "désactivé")

func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	var on: bool = mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if on else DisplayServer.WINDOW_MODE_FULLSCREEN)
	show_options()

# --- Overlay : montée de niveau ----------------------------------------------
func show_levelup(level: int) -> void:
	overlay_layer.visible = true
	_overlay_clear()
	_overlay_title("★ NIVEAU %d — choisis un talent" % level, Color(0.7, 1.0, 0.7))
	var pool: Array = Data.TALENTS.duplicate()
	pool.shuffle()
	for i in min(3, pool.size()):
		var t: Dictionary = pool[i]
		var btn := Ui.button("%s — %s" % [t["name"], t["desc"]], 46, 18)
		btn.pressed.connect(game.pick_talent.bind(t))
		overlay_content.add_child(btn)

# --- Overlay : inventaire -----------------------------------------------------
func show_inventory() -> void:
	overlay_layer.visible = true
	_overlay_clear()
	var player = game.player
	_overlay_title("SAC  (%d/%d)     Éclats : %d" % [game.inventory.size(), game.INV_CAP, game.run_shards], Color(0.82, 0.9, 1.0))

	_overlay_label("— Équipé —", Color(0.6, 0.85, 1.0))
	for slot in Data.SLOTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		if player.equipment.has(slot):
			var it: Dictionary = player.equipment[slot]
			var lbl := Ui.label("%s : %s  (%s)" % [Data.SLOT_NAMES[slot], it["name"], Data.bonus_summary(it["bonus"])], 15, it.get("rarity_color", Color.WHITE))
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lbl)
			var b := Ui.button("Déséquiper")
			b.pressed.connect(_inv_unequip.bind(slot))
			row.add_child(b)
		else:
			var lbl := Ui.label("%s : —" % Data.SLOT_NAMES[slot], 15, Color(0.5, 0.5, 0.58))
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lbl)
		overlay_content.add_child(row)
		if player.equipment.has(slot) and player.equipment[slot].get("desc", "") != "":
			overlay_content.add_child(Ui.label("   ✦ " + player.equipment[slot]["desc"], 12, Color(0.85, 0.7, 0.35), false, true, 700))

	_build_skill_panel(player)

	_overlay_label("— Objets —", Color(0.6, 0.85, 1.0))
	if game.inventory.is_empty():
		_overlay_label("(sac vide)", Color(0.5, 0.5, 0.58))
	for item in game.inventory:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		if item.get("kind", "") == "equip":
			var lbl := Ui.label("%s [%s]  (%s)" % [item["name"], item.get("rarity_name", ""), Data.bonus_summary(item["bonus"])], 15, item.get("rarity_color", Color.WHITE))
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lbl)
			var be := Ui.button("Équiper")
			be.pressed.connect(_inv_equip.bind(item))
			row.add_child(be)
		else:
			var lbl := Ui.label("%s  (consommable)" % item["name"], 15, item.get("color", Color.WHITE))
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lbl)
			var bu := Ui.button("Utiliser")
			bu.pressed.connect(_inv_use.bind(item))
			row.add_child(bu)
		var bsv := Ui.button("Recycler")
		bsv.pressed.connect(_inv_salvage.bind(item))
		row.add_child(bsv)
		overlay_content.add_child(row)
		if item.get("desc", "") != "":
			overlay_content.add_child(Ui.label("   ✦ " + item["desc"], 12, Color(0.85, 0.7, 0.35), false, true, 700))

	overlay_content.add_child(HSeparator.new())
	var close := Ui.button("Fermer   [I / Échap]", 42)
	close.pressed.connect(game.close_inventory)
	overlay_content.add_child(close)

## Panneau « Compétences » : compétence active sélectionnable (compatibles avec
## l'arme équipée), + liste des compétences apprises pour d'autres types.
func _build_skill_panel(player) -> void:
	var wtype: String = String(player.equipment.get("arme", {}).get("weapon_type", ""))
	var tname: String = Data.WEAPON_TYPE_NAME.get(wtype, "—")
	_overlay_label("— Compétences (arme : %s) —" % tname, Color(0.6, 0.85, 1.0))
	for id in game.selectable_skills():
		var s: Dictionary = Data.SKILLS[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var active: bool = id == player.active_skill_id
		var col: Color = Color(0.7, 1.0, 0.7) if active else Data.skill_rarity_color(id)
		var lbl := Ui.label("%s%s  —  %s  (cd %d, portée %d)" % ["★ " if active else "", s["name"], s["desc"], int(s["cd"]), int(s["range"])], 14, col)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		if active:
			row.add_child(Ui.label("active", 13, Color(0.6, 1.0, 0.6)))
		else:
			var b := Ui.button("Équiper")
			b.pressed.connect(_inv_select_skill.bind(id))
			row.add_child(b)
		overlay_content.add_child(row)
	# Compétences apprises mais incompatibles avec l'arme actuelle (info).
	var other: Array = []
	for id in game.known_skills:
		if String(Data.SKILLS.get(id, {}).get("wtype", "")) != wtype:
			other.append(id)
	if not other.is_empty():
		var names: Array = []
		for id in other:
			names.append("%s (%s)" % [Data.SKILLS[id]["name"], Data.WEAPON_TYPE_NAME[Data.SKILLS[id]["wtype"]]])
		overlay_content.add_child(Ui.label("Apprises (autre arme requise) : " + ", ".join(names), 12, Color(0.55, 0.55, 0.62), false, true, 700))

func _inv_select_skill(id: String) -> void:
	game.select_skill(id)
	show_inventory()

func _inv_equip(item: Dictionary) -> void:
	game.equip_item(item)
	show_inventory()

func _inv_unequip(slot: String) -> void:
	game.unequip_item(slot)
	show_inventory()

func _inv_salvage(item: Dictionary) -> void:
	game.salvage_item(item)
	show_inventory()

func _inv_use(item: Dictionary) -> void:
	game.use_consumable(item)
	show_inventory()

func _overlay_clear() -> void:
	for c in overlay_content.get_children():
		overlay_content.remove_child(c)
		c.queue_free()

func _overlay_title(txt: String, col: Color) -> void:
	overlay_content.add_child(Ui.label(txt, 24, col))
	overlay_content.add_child(HSeparator.new())

func _overlay_label(txt: String, col: Color) -> void:
	overlay_content.add_child(Ui.label(txt, 15, col))

# --- Rafraîchissement (lecture de l'état du jeu) ------------------------------
func refresh() -> void:
	var player = game.player
	if game.dungeon != null:
		sb_floor.text = "Étage %d — %s" % [game.floor_num, game.dungeon.biome.get("name", "")]
	else:
		sb_floor.text = "Étage %d" % game.floor_num
	sb_hero.text = player.display_name
	sb_hero.add_theme_color_override("font_color", player.color)
	hp_bar.max_value = max(1, player.max_hp)
	hp_bar.value = clampi(player.hp, 0, player.max_hp)
	hp_text.text = "PV  %d / %d" % [player.hp, player.max_hp]

	var need: int = game.xp_to_next(player.level)
	sb_level.text = "Niveau %d   (XP %d/%d)" % [player.level, player.xp, need]
	xp_bar.max_value = max(1, need)
	xp_bar.value = clampi(player.xp, 0, need)

	stat_labels["atk"].text = str(player.atk)
	stat_labels["magic"].text = str(player.magic)
	stat_labels["defense"].text = str(player.defense)
	stat_labels["speed"].text = str(player.speed)
	stat_labels["hp_regen"].text = str(player.hp_regen)
	stat_labels["vision"].text = str(player.vision)
	stat_labels["crit"].text = "%d%%" % int(round(player.crit_chance * 100.0))
	stat_labels["dodge"].text = "%d%%" % int(round(player.dodge_chance * 100.0))
	stat_labels["lifesteal"].text = "%d%%" % int(round(player.lifesteal_pct * 100.0))
	stat_labels["run_shards"].text = str(game.run_shards)
	stat_labels["bank"].text = str(GameState.shards)

	# Capacité active = compétence de l'arme équipée (cf. Entity.recompute_stats).
	var skill_name: String = "—"
	if player.ability_id != "" and Data.SKILLS.has(player.ability_id):
		skill_name = Data.SKILLS[player.ability_id]["name"]
	if player.ability_id == "":
		sb_ability.text = "Aucune arme équipée"
		sb_ability.add_theme_color_override("font_color", Color(0.6, 0.6, 0.68))
	elif player.ability_ready():
		sb_ability.text = "%s\n[ESPACE] — PRÊTE" % skill_name
		sb_ability.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	else:
		sb_ability.text = "%s\n[ESPACE] — recharge %d tour(s)" % [skill_name, player.ability_cd]
		sb_ability.add_theme_color_override("font_color", Color(0.85, 0.85, 0.5))

	_rebuild_equip()
	_rebuild_artifacts()
	_rebuild_powers()
	_rebuild_synergies()
	_rebuild_statuses()
	log_label.text = "\n".join(game.messages)

func _rebuild_equip() -> void:
	for c in equip_box.get_children():
		c.queue_free()
	for slot in Data.SLOTS:
		equip_box.add_child(Ui.label("%s %s" % [Data.SLOT_GLYPH[slot], Data.SLOT_NAMES[slot]], 13, Data.SLOT_COLOR[slot]))
		if game.player.equipment.has(slot):
			var it: Dictionary = game.player.equipment[slot]
			equip_box.add_child(Ui.label("%s  (%s)" % [it["name"], Data.bonus_summary(it["bonus"])], 14,
				it.get("rarity_color", Color(0.92, 0.95, 1.0)), false, true, SIDEBAR_W - 60))
			if it.get("desc", "") != "":
				equip_box.add_child(Ui.label("✦ " + it["desc"], 11, Color(0.85, 0.7, 0.35), false, true, SIDEBAR_W - 60))
		else:
			equip_box.add_child(Ui.label("— vide —", 14, Color(0.5, 0.5, 0.58)))

func _rebuild_artifacts() -> void:
	for c in artifact_box.get_children():
		c.queue_free()
	if game.player.artifacts.is_empty():
		artifact_box.add_child(Ui.label("— aucun —", 14, Color(0.5, 0.5, 0.58)))
		return
	for a in game.player.artifacts:
		artifact_box.add_child(Ui.label("✦ " + str(a.get("name", "?")), 14, Color(0.95, 0.75, 1.0)))
		artifact_box.add_child(Ui.label(str(a.get("desc", "")), 12, Color(0.65, 0.65, 0.72), false, true, SIDEBAR_W - 60))

func _rebuild_powers() -> void:
	for c in power_box.get_children():
		c.queue_free()
	if game.player.powers.is_empty():
		power_box.add_child(Ui.label("— aucun —", 14, Color(0.5, 0.5, 0.58)))
		return
	for p in game.player.powers:
		power_box.add_child(Ui.label("Ω " + str(p.get("name", "?")), 14, Color(1.0, 0.78, 0.45)))
		power_box.add_child(Ui.label(str(p.get("desc", "")), 12, Color(0.65, 0.65, 0.72), false, true, SIDEBAR_W - 60))

func _rebuild_synergies() -> void:
	for c in synergy_box.get_children():
		c.queue_free()
	var syns: Array = game.player.active_synergies
	if syns.is_empty():
		synergy_box.add_child(Ui.label("— aucune —", 14, Color(0.5, 0.5, 0.58)))
		return
	for s in syns:
		synergy_box.add_child(Ui.label("⚡ " + str(s["name"]), 14, s.get("color", Color(1.0, 0.9, 0.5))))
		synergy_box.add_child(Ui.label(str(s.get("desc", "")), 11, Color(0.7, 0.7, 0.78), false, true, SIDEBAR_W - 60))

const STATUS_LABEL := {
	"poison": ["☠ Poison", Color(0.62, 0.85, 0.4)],
	"burn": ["🔥 Brûlure", Color(1.0, 0.55, 0.3)],
	"slow": ["🐌 Ralenti", Color(0.6, 0.8, 1.0)],
	"stun": ["💫 Paralysé", Color(0.8, 0.75, 1.0)],
}

func _rebuild_statuses() -> void:
	for c in status_box.get_children():
		c.queue_free()
	var st: Array = game.player.statuses
	if st.is_empty():
		status_box.add_child(Ui.label("— aucun —", 14, Color(0.5, 0.5, 0.58)))
		return
	for s in st:
		var id: String = str(s["id"])
		var meta: Array = STATUS_LABEL.get(id, [id, Color.WHITE])
		var txt: String = str(meta[0])
		var stacks: int = int(s.get("stacks", 1))
		if (id == "poison" or id == "burn") and stacks > 1:
			txt += " ×%d" % stacks
		txt += "  (%d t)" % int(s["turns"])
		status_box.add_child(Ui.label(txt, 14, meta[1]))
