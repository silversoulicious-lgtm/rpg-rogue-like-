## Toute l'interface du jeu : sidebar permanente, journal, écran HUB (Pied de
## la Tour) et overlays (montée de niveau, inventaire).
## Lit l'état via une référence au jeu (game = Main) et appelle ses méthodes
## publiques sur les clics. Aucune logique de jeu ici : uniquement de l'affichage.
extends Node

const VIEW := Vector2(1280, 720)
const SIDEBAR_W := 384
const LOG_H := 88
const TURN_STRIP_H := 34    # bande d'ordre des tours, juste au-dessus du journal
const TURN_STRIP_N := 8     # nombre de tours prévisualisés
const VERSION := "v0.5 — accès anticipé"

# Pitch court par type d'arme, affiché sur la fiche de loadout.
const WEAPON_PITCH := {
	"melee": "Corps-à-corps · zone & encaisse",
	"ranged": "À distance · rapide & perçant",
	"magic": "Magie · effets & portée",
}

# [id, glyph, color, tooltip]
const STAT_ICONS := [
	["atk",        "⚔",  Color(0.90, 0.35, 0.35), "Attaque"],
	["magic",      "✦",  Color(0.65, 0.40, 1.00), "Magie"],
	["defense",    "◈",  Color(0.55, 0.70, 1.00), "Défense"],
	["speed",      "⚡", Color(1.00, 0.88, 0.30), "Vitesse"],
	["hp_regen",   "♥",  Color(0.35, 0.90, 0.45), "Régén PV/tour"],
	["vision",     "◎",  Color(0.40, 0.85, 1.00), "Vision"],
	["crit",       "✸",  Color(1.00, 0.65, 0.20), "Critique"],
	["dodge",      "◌",  Color(0.45, 0.85, 0.75), "Esquive"],
	["lifesteal",  "♦",  Color(0.85, 0.25, 0.45), "Vol de vie"],
	["run_shards", "◆",  Color(0.95, 0.78, 0.35), "Éclats (run)"],
	["bank",       "⊛",  Color(0.70, 0.70, 0.82), "Banque"],
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
var hub_layer: CanvasLayer
var turn_strip: HBoxContainer
var _turn_strip_ids: Array = []      # cache : ne reconstruit que si l'ordre a changé
# Empreintes des sections sidebar reconstruites à chaque refresh() (plusieurs
# fois par tour) — ne reconstruire les nœuds que si le contenu a changé.
var _relic_fp: String = ""
var _synergy_fp: String = ""
var _status_fp: String = ""
# Sidebar
var sb_floor: Label
var sb_hero: Label
var sb_level: Label
var sb_ability: Label
var hp_bar: ProgressBar
var hp_text: Label
var xp_bar: ProgressBar
var stat_labels: Dictionary = {}
var equip_panel: Control
var relic_box: VBoxContainer     # Phase 6.4 : artefacts + pouvoirs unifiés
var synergy_box: VBoxContainer
var status_box: VBoxContainer
var inspect_box: VBoxContainer

func setup(game_ref) -> void:
	game = game_ref
	_build_hud()
	_build_menu()
	_build_overlay()
	_build_hub_ui()

func play_area() -> Vector2:
	return get_viewport().get_visible_rect().size - Vector2(SIDEBAR_W, LOG_H + TURN_STRIP_H)

# --- Construction -------------------------------------------------------------
func _build_hud() -> void:
	hud_layer = CanvasLayer.new()
	add_child(hud_layer)
	_build_sidebar()
	_build_turn_strip()
	_build_log()

func _build_sidebar() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -SIDEBAR_W
	panel.offset_right = 0
	panel.add_theme_stylebox_override("panel", Ui.panel_style(Color(0.072, 0.065, 0.115)))
	hud_layer.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var v := Ui.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.custom_minimum_size = Vector2(SIDEBAR_W - 56, 0)
	scroll.add_child(v)

	# Titre avec liseré décoratif
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	title_row.add_child(Ui.label("⛫", 16, Color(0.72, 0.62, 1.0)))
	title_row.add_child(Ui.label("LES STRATES", 16, Color(0.72, 0.62, 1.0)))
	v.add_child(title_row)
	v.add_child(_hdivider_full())

	sb_floor = Ui.label("", 14, Color(1.0, 0.85, 0.35)); v.add_child(sb_floor)
	sb_hero = Ui.label("", 16, Color(0.92, 0.88, 1.0)); v.add_child(sb_hero)

	# HP : texte et barre sur la même ligne
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 6)
	hp_text = Ui.label("", 13); hp_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hp_row.add_child(hp_text)
	v.add_child(hp_row)
	hp_bar = Ui.progress_bar(12, Color(0.3, 0.8, 0.35), Color(0.25, 0.07, 0.07)); v.add_child(hp_bar)

	# XP
	var xp_row := HBoxContainer.new()
	xp_row.add_theme_constant_override("separation", 6)
	sb_level = Ui.label("", 12, Color(0.7, 0.95, 0.7)); sb_level.size_flags_horizontal = Control.SIZE_EXPAND_FILL; xp_row.add_child(sb_level)
	v.add_child(xp_row)
	xp_bar = Ui.progress_bar(5, Color(0.55, 0.85, 0.4), Color(0.12, 0.15, 0.1), 3); v.add_child(xp_bar)

	# Stats : grille 4 colonnes avec icônes
	v.add_child(_section("STATS"))
	var stat_grid := GridContainer.new()
	stat_grid.columns = 4
	stat_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stat_grid.add_theme_constant_override("h_separation", 4)
	stat_grid.add_theme_constant_override("v_separation", 4)
	v.add_child(stat_grid)
	for s in STAT_ICONS:
		stat_grid.add_child(_stat_cell(s[0], s[1], s[2], s[3]))

	v.add_child(_section("CAPACITÉ"))
	sb_ability = Ui.label("", 13, Color.WHITE, false, true, SIDEBAR_W - 56); v.add_child(sb_ability)
	v.add_child(_section("ÉTATS"))
	status_box = Ui.vbox(3); v.add_child(status_box)
	v.add_child(_section("INSPECTION"))
	inspect_box = Ui.vbox(3); v.add_child(inspect_box)
	show_inspect(null)
	v.add_child(_section("ÉQUIPEMENT"))
	equip_panel = load("res://scripts/EquipPanel.gd").new()
	equip_panel.custom_minimum_size = Vector2(SIDEBAR_W - 56, 148)
	v.add_child(equip_panel)
	# Phase 6.4 : artefacts et pouvoirs fusionnés en une seule section « Reliques ».
	v.add_child(_section("RELIQUES"))
	relic_box = Ui.vbox(5); v.add_child(relic_box)
	v.add_child(_section("SYNERGIES"))
	synergy_box = Ui.vbox(4); v.add_child(synergy_box)
	v.add_child(Ui.label("[I] Inventaire", 11, Color(0.45, 0.65, 0.88)))

func _section(txt: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var l := _hdivider_full(); row.add_child(l)
	row.add_child(Ui.label("✦ %s ✦" % txt, 10, Color(0.45, 0.65, 0.88)))
	var r := _hdivider_full(); row.add_child(r)
	return row

func _hdivider_full() -> Control:
	var c := ColorRect.new()
	c.color = Color(0.28, 0.38, 0.58, 0.65)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.custom_minimum_size = Vector2(10, 1)
	return c

func _stat_cell(sid: String, glyph: String, col: Color, tip: String) -> Control:
	var cell := VBoxContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.tooltip_text = tip
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	cell.add_theme_constant_override("separation", 2)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r * 0.14, col.g * 0.14, col.b * 0.18)
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(1)
	sb.border_color = col.darkened(0.25)
	sb.content_margin_left = 2; sb.content_margin_right = 2
	sb.content_margin_top = 2; sb.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", sb)
	var gl := Ui.label(glyph, 14, col.lightened(0.2), true)
	gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(gl)
	cell.add_child(panel)
	var val := Ui.label("—", 11, Color(0.88, 0.88, 0.95), true)
	val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(val)
	stat_labels[sid] = val
	return cell

## Bande d'ordre des tours : n mini-portraits juste au-dessus du journal,
## rendent visible l'économie d'énergie/vitesse (cf. Main.preview_turn_order).
func _build_turn_strip() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 12
	panel.offset_right = -SIDEBAR_W - 12
	panel.offset_top = -(LOG_H + TURN_STRIP_H)
	panel.offset_bottom = -LOG_H
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	hud_layer.add_child(panel)

	turn_strip = Ui.hbox(4)
	panel.add_child(turn_strip)

func _build_log() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 12
	panel.offset_right = -SIDEBAR_W - 12
	panel.offset_top = -LOG_H
	panel.offset_bottom = -10
	panel.add_theme_stylebox_override("panel", Ui.panel_style(Color(0.08, 0.07, 0.11)))
	hud_layer.add_child(panel)

	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.fit_content = false
	log_label.scroll_active = true
	panel.add_child(log_label)

func _build_menu() -> void:
	menu_layer = CanvasLayer.new()
	menu_layer.layer = 2
	add_child(menu_layer)
	menu_bg = Ui.gradient_bg(Color(0.105, 0.075, 0.165), Color(0.012, 0.010, 0.028))
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

# --- Hub (Pied de la Tour) -----------------------------------------------------
## Bandeau minimal (pas de sidebar de combat, rien à afficher hors-run) :
## indice de jeu + accès direct au menu principal sans avoir à marcher nulle part.
func _build_hub_ui() -> void:
	hub_layer = CanvasLayer.new()
	hub_layer.layer = 1
	hub_layer.visible = false
	add_child(hub_layer)

	var hint := PanelContainer.new()
	hint.add_theme_stylebox_override("panel", Ui.panel_style(Color(0.06, 0.05, 0.09, 0.75)))
	hint.position = Vector2(24, 20)
	hub_layer.add_child(hint)
	hint.add_child(Ui.label("⛫ Pied de la Tour — approche un bâtiment pour y entrer.", 15, Ui.INK))

	var back := Ui.button("↩ Menu principal", 40, 14)
	back.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	back.position = Vector2(-216, 20)
	back.pressed.connect(game.return_to_title)
	hub_layer.add_child(back)

func show_hub() -> void:
	menu_layer.visible = false
	overlay_layer.visible = false
	hud_layer.visible = false
	hub_layer.visible = true

## Écran "bientôt disponible" pour les bâtiments du Hub pas encore conçus
## (Forge/Boutique : nouveaux systèmes de progression, cf. RESUME_SESSION.md).
func show_hub_stub(title: String, desc: String) -> void:
	overlay_layer.visible = true
	_overlay_clear()
	_overlay_title(title, Color(0.85, 0.8, 0.5))
	_overlay_label(desc, Color(0.75, 0.75, 0.82))
	overlay_content.add_child(HSeparator.new())
	var back := Ui.button("Retour", 44, 16)
	back.pressed.connect(game.enter_hub)
	overlay_content.add_child(back)

# --- Overlays boutique / événement / repos ------------------------------------
func show_shop(stock: Array, shards: int) -> void:
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
	_focus_first_button()

## Récompense de fin d'étage (Phase 4) : choisir 1 butin parmi ceux proposés.
func show_floor_reward(rewards: Array, is_elite: bool) -> void:
	overlay_layer.visible = true
	_overlay_clear()
	var title: String = "☠ BUTIN D'ÉLITE — choisis ta récompense" if is_elite else "✦ BUTIN — choisis ta récompense"
	_overlay_title(title, Color(1.0, 0.85, 0.4) if not is_elite else Color(1.0, 0.6, 0.4))
	_overlay_label("Un seul de ces butins t'accompagnera. Choisis selon ta route.", Color(0.75, 0.75, 0.82))
	overlay_content.add_child(HSeparator.new())
	for i in rewards.size():
		var r: Dictionary = rewards[i]
		var btn := Ui.button(String(r["label"]), 48, 17)
		btn.add_theme_color_override("font_color", r.get("color", Color.WHITE))
		btn.pressed.connect(game.resolve_floor_reward.bind(i))
		overlay_content.add_child(btn)
		if r.get("desc", "") != "":
			overlay_content.add_child(Ui.label("   " + String(r["desc"]), 12, Color(0.7, 0.7, 0.78), false, true, 700))
	_focus_first_button()

## Écho d'Aria vaincu (Phase 6.8) : réclamer UN objet de son équipement.
func show_echo_claim(items: Array) -> void:
	overlay_layer.visible = true
	_overlay_clear()
	_overlay_title("✶ ÉCHO VAINCU — réclame une relique", Color(0.78, 0.68, 1.0))
	_overlay_label("Le fantôme de ton dernier run cède l'un de ses objets. Un seul.", Color(0.75, 0.75, 0.82))
	overlay_content.add_child(HSeparator.new())
	for i in items.size():
		var it: Dictionary = items[i]
		var btn := Ui.button("%s  (%s)" % [String(it.get("name", "?")), Data.bonus_summary(it.get("bonus", {}))], 46, 16)
		btn.add_theme_color_override("font_color", it.get("rarity_color", Color.WHITE))
		btn.pressed.connect(game.claim_echo_item.bind(i))
		overlay_content.add_child(btn)
	var skip := Ui.button("Ne rien prendre", 42, 15)
	skip.pressed.connect(game.claim_echo_item.bind(-1))
	overlay_content.add_child(skip)
	_focus_first_button()

func show_event(event: Dictionary) -> void:
	overlay_layer.visible = true
	_overlay_clear()
	_overlay_title("❔ %s" % event["title"], Color(0.7, 0.85, 1.0))
	_overlay_label(event["desc"], Color(0.75, 0.75, 0.82))
	overlay_content.add_child(HSeparator.new())
	for i in event["choices"].size():
		var btn := Ui.button(event["choices"][i]["label"], 46, 17)
		btn.pressed.connect(game.resolve_event.bind(i))
		overlay_content.add_child(btn)
	_focus_first_button()

func show_rest() -> void:
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
	if GameState.forge_unlocked():
		var b3 := Ui.button("Forger   (renforce une pièce d'équipement)", 46, 17)
		b3.pressed.connect(game.rest_choice.bind("forge"))
		overlay_content.add_child(b3)
	_focus_first_button()

## Forge Itinérante (Phase 5) : choisir la pièce d'équipement à renforcer
## (~30% de bonus supplémentaires) plutôt qu'un choix aléatoire silencieux.
func show_forge(equipment: Dictionary) -> void:
	overlay_layer.visible = true
	_overlay_clear()
	_overlay_title("⚒ FORGE ITINÉRANTE", Color(1.0, 0.75, 0.35))
	_overlay_label("Choisis la pièce à renforcer : ses bonus actuels augmentent d'environ 30%.", Color(0.75, 0.75, 0.82))
	overlay_content.add_child(HSeparator.new())
	for slot in Data.SLOTS:
		if not equipment.has(slot):
			continue
		var it: Dictionary = equipment[slot]
		var btn := Ui.button("%s : %s  (%s)" % [Data.SLOT_NAMES[slot], it["name"], Data.bonus_summary(it["bonus"])], 46, 15)
		btn.add_theme_color_override("font_color", it.get("rarity_color", Color.WHITE))
		btn.pressed.connect(game.forge_choice.bind(slot))
		overlay_content.add_child(btn)
	overlay_content.add_child(HSeparator.new())
	var back := Ui.button("Renoncer", 40)
	back.pressed.connect(game.forge_cancel)
	overlay_content.add_child(back)
	_focus_first_button()

# --- Écran-titre --------------------------------------------------------------
# Chemin de l'illustration finale (Aria devant la Tour). Tant qu'elle n'existe
# pas, TitleBg.gd dessine une silhouette procédurale de repli — dès que ce
# fichier est ajouté à assets/, il prend automatiquement le relais, sans
# changement de code.
const TITLE_BG_PATH := "res://assets/title_bg.png"

func show_title() -> void:
	_menu_show()
	_menu_clear()

	# --- Fond : illustration si présente, sinon silhouette procédurale ----------
	if ResourceLoader.exists(TITLE_BG_PATH):
		var tr := TextureRect.new()
		tr.texture = load(TITLE_BG_PATH)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		menu_root.add_child(tr)
	else:
		var placeholder := Control.new()
		placeholder.set_script(load("res://scripts/TitleBg.gd"))
		placeholder.set_anchors_preset(Control.PRESET_FULL_RECT)
		menu_root.add_child(placeholder)

	# Voiles de contraste : assombrit le haut (lisibilité du titre) et le bas
	# (lisibilité du menu), quel que soit le contenu de l'image de fond.
	# Ui.gradient_bg() ancre déjà en PRESET_FULL_RECT ; on retaille chaque voile
	# à sa bande d'écran via un offset explicite (assigner .size seul serait
	# écrasé par les ancres au premier redimensionnement).
	var shade_top := Ui.gradient_bg(Color(0.02, 0.015, 0.04, 0.55), Color(0.02, 0.015, 0.04, 0.0))
	shade_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	shade_top.offset_bottom = VIEW.y * 0.32
	menu_root.add_child(shade_top)
	var shade_bottom := Ui.gradient_bg(Color(0.02, 0.015, 0.04, 0.0), Color(0.02, 0.015, 0.04, 0.92))
	shade_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	shade_bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	shade_bottom.offset_top = -VIEW.y * 0.40
	menu_root.add_child(shade_bottom)

	# --- Bloc-titre, ancré en haut à gauche -------------------------------------
	var title_col := Ui.vbox(4)
	title_col.set_anchors_preset(Control.PRESET_TOP_LEFT)
	title_col.offset_left = 48
	title_col.offset_top = 40
	menu_root.add_child(title_col)
	title_col.add_child(Ui.label("⛫  L E S   S T R A T E S", 36, Ui.INK))
	title_col.add_child(Ui.label("Roguelike d'ascension — grimpe la tour, strate par strate.", 14, Ui.MUTED))

	# --- Bloc-menu, ancré en bas à droite dans un panneau semi-transparent ------
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Ui.panel_style(Color(0.07, 0.06, 0.11, 0.78)))
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -48
	panel.offset_bottom = -40
	menu_root.add_child(panel)
	var col := Ui.vbox(8)
	col.custom_minimum_size = Vector2(340, 0)
	panel.add_child(col)

	var play := Ui.menu_button("▶   Nouvelle Ascension", 300.0)
	play.pressed.connect(game.enter_hub)
	col.add_child(play)
	var sanct := Ui.menu_button("✦   Sanctuaire  (%d Éclats)" % GameState.shards, 300.0, 15)
	sanct.pressed.connect(game.open_meta)
	col.add_child(sanct)
	var know := Ui.menu_button("✶   Arbre de Connaissances  (%d)" % GameState.knowledge, 300.0, 15)
	know.pressed.connect(game.open_knowledge)
	col.add_child(know)
	var opt := Ui.menu_button("⚙   Options", 300.0, 15)
	opt.pressed.connect(show_options)
	col.add_child(opt)
	var quit := Ui.menu_button("✕   Quitter", 300.0, 15)
	quit.pressed.connect(game.quit_game)
	col.add_child(quit)

	# --- Bandeau de profil, ancré en bas à gauche -------------------------------
	var foot_col := Ui.vbox(6)
	foot_col.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot_col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot_col.offset_left = 48
	foot_col.offset_bottom = -40
	menu_root.add_child(foot_col)
	foot_col.add_child(_title_profile_strip())
	foot_col.add_child(Ui.label(VERSION, 12, Color(0.45, 0.45, 0.55)))

## Bandeau de profil du menu-titre : record d'ascension + monnaies méta, pour
## donner l'impression d'un profil persistant plutôt qu'une ligne isolée.
func _title_profile_strip() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	if GameState.best_floor > 1:
		row.add_child(Ui.label("⛰ Étage %d" % GameState.best_floor, 13, Ui.GOLD))
	row.add_child(Ui.label("✦ %d" % GameState.shards, 13, Color(0.85, 0.78, 0.5)))
	row.add_child(Ui.label("✶ %d" % GameState.knowledge, 13, Color(0.65, 0.75, 0.95)))
	return row

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
	back.pressed.connect(game.return_to_previous)
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
	back.pressed.connect(game.return_to_previous)
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
	if GameState.codex_unlocked():
		var codex := Ui.menu_button("📖   Consulter le Codex", 360.0, 16)
		codex.pressed.connect(game.open_codex)
		col.add_child(codex)
	var back := Ui.menu_button("↩   Menu principal", 360.0, 16)
	back.pressed.connect(game.return_to_previous)
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

# --- Codex (catalogue des découvertes) ----------------------------------------
func show_codex() -> void:
	_menu_show()
	var col := _menu_column(820.0, true)
	col.add_child(Ui.label("📖  CODEX", 30, Color(0.7, 0.85, 1.0), true))
	col.add_child(Ui.label("Tout ce que tu as rencontré dans la Tour. Chaque première rencontre t'a appris quelque chose.", 14, Ui.MUTED, true, true, 760))
	col.add_child(HSeparator.new())

	var skill_ids: Array = []
	for sid in Data.SKILLS:
		if String(Data.SKILLS[sid]["rarity"]) != "base":
			skill_ids.append(sid)
	_codex_section(col, "⚔ Compétences", "skill", skill_ids,
		func(id): return String(Data.SKILLS[id]["name"]))
	# Phase 6.4 : Codex des Reliques (artefacts + pouvoirs unifiés).
	var relic_ids: Array = []
	for r in Data.relics():
		relic_ids.append(r["id"])
	_codex_section(col, "✦Ω Reliques", "relic", relic_ids, func(id): return _relic_name(id))
	var uniq_names: Array = []
	for u in Data.UNIQUE_ITEMS:
		if not uniq_names.has(u["name"]):
			uniq_names.append(u["name"])
	_codex_section(col, "✦ Objets uniques", "unique", uniq_names, func(n): return String(n))
	_codex_bestiary(col)

	col.add_child(HSeparator.new())
	var back := Ui.menu_button("↩   Retour à l'Arbre", 360.0, 16)
	back.pressed.connect(game.open_knowledge)
	col.add_child(back)

func _relic_name(id: String) -> String:
	for r in Data.relics():
		if String(r["id"]) == id:
			return String(r["name"])
	return id

## Bestiaire (Phase 6.5) : liste ENEMIES + BOSSES. Nom révélé au 1er kill,
## ligne de traits à partir de KILL_TRAITS_THRESHOLD kills, compteur de mises à mort.
func _codex_bestiary(col: VBoxContainer) -> void:
	var all: Array = []
	for e in Data.ENEMIES:
		all.append(e)
	for b in Data.BOSSES:
		all.append(b)
	var seen: Dictionary = GameState.discovered.get("monster", {})
	col.add_child(Ui.label("☠ Bestiaire   (%d / %d)" % [seen.size(), all.size()], 18, Color(0.8, 0.85, 0.95), true))
	for def in all:
		var sprite: String = String(def.get("sprite", ""))
		if seen.has(sprite):
			var kills: int = GameState.kills_of(sprite)
			col.add_child(Ui.label("  ✓ %s   ×%d" % [str(def.get("name", "?")), kills], 14, Color(0.85, 0.9, 0.8)))
			if kills >= GameState.KILL_TRAITS_THRESHOLD:
				col.add_child(Ui.label("      " + enemy_traits_line(def), 12, Color(0.6, 0.65, 0.72), false, true, 740))
		else:
			col.add_child(Ui.label("  ??? — non découvert", 14, Color(0.45, 0.45, 0.52)))
	col.add_child(_spacer(8))

## Résumé FR des traits d'un ennemi (partagé avec l'inspection, Phase 2.7) :
## comportement + effet au contact + résistances/faiblesses/meute notables.
func enemy_traits_line(def: Dictionary) -> String:
	var ai: Dictionary = def.get("ai", {})
	var parts: Array = [BEHAVIOR_LABEL.get(String(ai.get("behavior", "melee")), "Corps à corps")]
	var oh: Dictionary = ai.get("on_hit", {})
	if not oh.is_empty():
		var sid: String = String(oh.get("id", ""))
		parts.append("au contact : " + str(STATUS_LABEL.get(sid, [sid, Color.WHITE])[0]))
	if float(ai.get("resist_phys", 0.0)) > 0.0:
		parts.append("résiste au physique")
	if float(ai.get("resist_magic", 0.0)) > 0.0:
		parts.append("résiste à la magie")
	if float(ai.get("weak_fire", 0.0)) > 0.0:
		parts.append("craint le feu")
	if bool(ai.get("pack", false)):
		parts.append("meute")
	if bool(ai.get("immune_fire", false)):
		parts.append("insensible au feu")
	return ", ".join(parts)

## Affiche une section du Codex : titre + compteur + liste (découverts en clair,
## inconnus masqués en « ??? »).
func _codex_section(col: VBoxContainer, title: String, category: String, ids: Array, namer: Callable) -> void:
	col.add_child(Ui.label("%s   (%d / %d)" % [title, GameState.discovered_count(category), ids.size()], 18, Color(0.8, 0.85, 0.95), true))
	var bucket: Dictionary = GameState.discovered.get(category, {})
	for id in ids:
		if bucket.has(id):
			col.add_child(Ui.label("  ✓ " + str(namer.call(id)), 14, Color(0.85, 0.9, 0.8)))
		else:
			col.add_child(Ui.label("  ??? — non découvert", 14, Color(0.45, 0.45, 0.52)))
	col.add_child(_spacer(8))

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
	var killed_by: String = str(r.get("killed_by", ""))
	if killed_by != "":
		col.add_child(Ui.label("Terrassée par %s." % killed_by, 15, Color(1.0, 0.55, 0.5), true))
	col.add_child(Ui.label("Étage atteint : %d        Niveau : %d" % [int(r.get("floor", 1)), int(r.get("level", 1))], 15, Color(0.85, 0.85, 0.92), true))
	var prev_best: int = int(r.get("prev_best_floor", GameState.best_floor))
	var gap: int = prev_best - int(r.get("floor", 1))
	if gap > 0 and gap <= 3:
		col.add_child(Ui.label("À %d étage(s) de ton record." % gap, 14, Color(0.85, 0.75, 0.5), true))
	col.add_child(Ui.label("Ennemis vaincus : %d        Meilleur coup : %d" % [int(r.get("kills", 0)), int(r.get("best_hit", 0))], 15, Color(0.85, 0.85, 0.92), true))
	col.add_child(Ui.label("Éclats du run : %d   (banque : %d)" % [int(r.get("shards", 0)), GameState.shards], 15, Color(1.0, 0.85, 0.35), true))
	var item_name: String = str(r.get("item", ""))
	if item_name != "":
		col.add_child(Ui.label("Objet le plus marquant : %s" % item_name, 15, Color.html(str(r.get("item_color", "d2d2e0"))), true))
	col.add_child(Ui.label("Records — Étage %d · %d ennemis vaincus" % [GameState.best_floor, GameState.best_kills], 14, Color(0.7, 0.95, 0.7), true))
	var timeline: Array = r.get("timeline", [])
	if not timeline.is_empty():
		col.add_child(_spacer(4))
		col.add_child(Ui.label("— Chronologie —", 14, Color(0.6, 0.85, 1.0), true))
		var start_i: int = maxi(0, timeline.size() - 10)
		for i in range(start_i, timeline.size()):
			col.add_child(Ui.label(str(timeline[i]), 12, Color(0.75, 0.75, 0.82), true))
	col.add_child(Ui.label("Seed du run : %d" % int(r.get("seed", 0)), 11, Color(0.5, 0.5, 0.58), true))

# --- Options (overlay au-dessus du menu) --------------------------------------
func show_options() -> void:
	overlay_layer.visible = true
	_overlay_clear()
	_overlay_title("⚙  OPTIONS", Ui.ACCENT_SOFT)
	var fs := Ui.button(_fullscreen_label(), 46, 17)
	fs.pressed.connect(_toggle_fullscreen)
	overlay_content.add_child(fs)
	overlay_content.add_child(HSeparator.new())
	overlay_content.add_child(_volume_row("Volume effets", "sfx_vol"))
	overlay_content.add_child(_volume_row("Volume musique", "music_vol"))
	var shake := CheckButton.new()
	shake.text = "Tremblement d'écran"
	shake.button_pressed = bool(GameState.settings.get("screenshake", true))
	shake.toggled.connect(func(v): GameState.settings["screenshake"] = v; GameState.save_game())
	overlay_content.add_child(shake)
	overlay_content.add_child(HSeparator.new())
	overlay_content.add_child(Ui.label("Commandes", 16, Color(0.6, 0.85, 1.0)))
	overlay_content.add_child(Ui.label("Déplacer : WASD / flèches / HJKL    Capacité : ESPACE", 13, Ui.MUTED))
	overlay_content.add_child(Ui.label("Attendre : .    Inventaire : I    Pause : Échap", 13, Ui.MUTED))
	overlay_content.add_child(HSeparator.new())
	var back := Ui.button("Retour", 44, 16)
	back.pressed.connect(hide_overlay)
	overlay_content.add_child(back)

func _volume_row(label_txt: String, key: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(Ui.label(label_txt, 14, Ui.INK, false, false, 130))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(GameState.settings.get(key, 0.8))
	slider.custom_minimum_size = Vector2(180, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v): GameState.settings[key] = v)
	slider.drag_ended.connect(func(_changed): GameState.save_game(); Sfx.play("ui"))
	row.add_child(slider)
	return row

func _fullscreen_label() -> String:
	var mode := DisplayServer.window_get_mode()
	var on: bool = mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	return "Plein écran : %s" % ("ACTIVÉ" if on else "désactivé")

func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	var on: bool = mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if on else DisplayServer.WINDOW_MODE_FULLSCREEN)
	show_options()

# --- Overlay : pause -----------------------------------------------------------
func show_pause() -> void:
	overlay_layer.visible = true
	_overlay_clear()
	_overlay_title("⏸  PAUSE", Ui.ACCENT_SOFT)
	var resume := Ui.button("▶  Reprendre", 46, 18)
	resume.pressed.connect(game.close_pause)
	overlay_content.add_child(resume)
	var opts := Ui.button("⚙  Options", 46, 17)
	opts.pressed.connect(show_options)
	overlay_content.add_child(opts)
	overlay_content.add_child(HSeparator.new())
	var abandon := Ui.button("✖  Abandonner l'ascension", 46, 16)
	abandon.pressed.connect(game.abandon_run)
	overlay_content.add_child(abandon)
	overlay_content.add_child(HSeparator.new())
	overlay_content.add_child(Ui.label("Seed du run : %d" % game.run_seed, 12, Ui.MUTED))
	var copy_seed := Ui.button("Copier la seed dans le journal", 36, 13)
	copy_seed.pressed.connect(func(): game.add_message("Seed du run : %d" % game.run_seed))
	overlay_content.add_child(copy_seed)
	_focus_first_button()

# --- Overlay : montée de niveau ----------------------------------------------
func show_levelup(level: int) -> void:
	overlay_layer.visible = true
	_overlay_clear()
	_overlay_title("★ NIVEAU %d — choisis un talent" % level, Color(0.7, 1.0, 0.7))
	for t in game.roll_talent_choices():
		var btn := Ui.button("%s — %s" % [t["name"], t["desc"]], 46, 18)
		btn.pressed.connect(game.pick_talent.bind(t))
		overlay_content.add_child(btn)
	_focus_first_button()

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

## Navigation clavier des overlays : place le focus sur le 1er bouton du
## panneau — la chaîne de focus native de Godot (flèches/Tab + Entrée) fait
## le reste sans code supplémentaire. À appeler en fin de chaque show_*.
func _focus_first_button() -> void:
	var btn: Button = _first_button(overlay_content)
	if btn != null:
		btn.grab_focus()

func _first_button(node: Node) -> Button:
	for c in node.get_children():
		if c is Button:
			return c
		var found: Button = _first_button(c)
		if found != null:
			return found
	return null

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
	_rebuild_relics()
	_rebuild_synergies()
	_rebuild_statuses()
	_rebuild_turn_strip()
	log_label.text = "\n".join(game.messages)
	log_label.scroll_to_line(log_label.get_line_count() - 1)

## Ne reconstruit la bande d'ordre des tours que si l'ordre calculé a changé
## (cache une liste d'instance_id) — évite de recréer des TextureRect à chaque
## rafraîchissement (plusieurs fois par tour).
func _rebuild_turn_strip() -> void:
	var order: Array = game.preview_turn_order(TURN_STRIP_N)
	var ids: Array = []
	for e in order:
		ids.append(e.get_instance_id())
	if ids == _turn_strip_ids:
		return
	_turn_strip_ids = ids
	for c in turn_strip.get_children():
		turn_strip.remove_child(c)
		c.queue_free()
	for e in order:
		var is_player: bool = e.faction == Entity.Faction.PLAYER
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(26, 26)
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.08, 0.07, 0.11, 0.9)
		box.set_border_width_all(2 if is_player else 1)
		box.border_color = Ui.ACCENT if is_player else Color(0.4, 0.38, 0.5, 0.6)
		box.set_corner_radius_all(4)
		box.set_content_margin_all(1)
		slot.add_theme_stylebox_override("panel", box)
		var path := "res://assets/%s.png" % e.sprite
		if e.sprite != "" and ResourceLoader.exists(path):
			var tr := TextureRect.new()
			tr.texture = load(path)
			tr.custom_minimum_size = Vector2(22, 22)
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			slot.add_child(tr)
		else:
			slot.add_child(Ui.label(e.glyph, 14, e.color, true))
		turn_strip.add_child(slot)

func _rebuild_equip() -> void:
	equip_panel.refresh(game.player.equipment)

## Phase 6.4 : section « Reliques » unique, alimentée par player.relics (stockage
## unifié). Glyphe selon le tier : ✦ artefact, Ω pouvoir.
func _rebuild_relics() -> void:
	var relics: Array = game.player.relics
	var fp: String = ",".join(relics.map(func(r): return str(r.get("tier", "?")) + ":" + str(r.get("name", "?"))))
	if fp == _relic_fp:
		return
	_relic_fp = fp
	for c in relic_box.get_children():
		c.queue_free()
	if relics.is_empty():
		relic_box.add_child(Ui.label("— aucune —", 14, Color(0.5, 0.5, 0.58)))
		return
	for r in relics:
		var is_art: bool = String(r.get("tier", "")) == "artifact"
		var glyph: String = "✦ " if is_art else "Ω "
		var col: Color = Color(0.95, 0.75, 1.0) if is_art else Color(1.0, 0.78, 0.45)
		relic_box.add_child(Ui.label(glyph + str(r.get("name", "?")), 14, col))
		relic_box.add_child(Ui.label(str(r.get("desc", "")), 12, Color(0.65, 0.65, 0.72), false, true, SIDEBAR_W - 60))

func _rebuild_synergies() -> void:
	var syns: Array = game.player.active_synergies
	var fp: String = ",".join(syns.map(func(s): return str(s.get("name", "?"))))
	if fp == _synergy_fp:
		return
	_synergy_fp = fp
	for c in synergy_box.get_children():
		c.queue_free()
	if syns.is_empty():
		synergy_box.add_child(Ui.label("— aucune —", 14, Color(0.5, 0.5, 0.58)))
		return
	for s in syns:
		synergy_box.add_child(Ui.label("⚡ " + str(s["name"]), 14, s.get("color", Color(1.0, 0.9, 0.5))))
		synergy_box.add_child(Ui.label(str(s.get("desc", "")), 11, Color(0.7, 0.7, 0.78), false, true, SIDEBAR_W - 60))

const STATUS_LABEL := {
	"poison": ["☠ Poison", Color(0.62, 0.85, 0.4)],
	"burn": ["🔥 Brûlure", Color(1.0, 0.55, 0.3)],
	"bleed": ["🩸 Saignement", Color(0.85, 0.25, 0.3)],
	"disease": ["🤢 Maladie", Color(0.55, 0.7, 0.35)],
	"slow": ["🐌 Ralenti", Color(0.6, 0.8, 1.0)],
	"stun": ["💫 Paralysé", Color(0.8, 0.75, 1.0)],
	"weaken": ["🛡 Défense ↓", Color(0.9, 0.65, 0.5)],
	"confusion": ["💫 Confusion", Color(0.85, 0.6, 1.0)],
}

func _rebuild_statuses() -> void:
	var st: Array = game.player.statuses
	var fp: String = ",".join(st.map(func(s): return "%s:%d:%d" % [str(s["id"]), int(s.get("stacks", 1)), int(s["turns"])]))
	if fp == _status_fp:
		return
	_status_fp = fp
	for c in status_box.get_children():
		c.queue_free()
	if st.is_empty():
		status_box.add_child(Ui.label("— aucun —", 14, Color(0.5, 0.5, 0.58)))
		return
	for s in st:
		var id: String = str(s["id"])
		var meta: Array = STATUS_LABEL.get(id, [id, Color.WHITE])
		var txt: String = str(meta[0])
		var stacks: int = int(s.get("stacks", 1))
		if (id == "poison" or id == "burn" or id == "bleed" or id == "disease") and stacks > 1:
			txt += " ×%d" % stacks
		txt += "  (%d t)" % int(s["turns"])
		status_box.add_child(Ui.label(txt, 14, meta[1]))

const BEHAVIOR_LABEL := {
	"melee": "Corps à corps", "ranged": "Tireur", "caster": "Invocateur/Hurleuse",
	"charger": "Chargeur", "fleer": "Fuyard", "teleporter": "Insaisissable",
	"ambush": "Mimique", "stationary": "Gardien lié",
}

## Section INSPECTION (survol souris, cf. MapView.tile_at_mouse) : détail de
## l'ennemi visible survolé. `e` peut être null (rien survolé -> placeholder).
## TODO parité clavier : pas d'inspection au clavier pour l'instant, souris seule.
func show_inspect(e) -> void:
	for c in inspect_box.get_children():
		c.queue_free()
	if e == null:
		inspect_box.add_child(Ui.label("— survole un ennemi —", 12, Color(0.5, 0.5, 0.58)))
		return
	inspect_box.add_child(Ui.label(str(e.display_name), 14, e.color, false, true, SIDEBAR_W - 60))
	inspect_box.add_child(Ui.label("PV %d / %d" % [e.hp, e.max_hp], 12, Color(0.85, 0.85, 0.92)))
	var atk_line: String = "ATK %d" % e.atk
	if e.ai.get("pack", false):
		atk_line += "  (meute)"
	inspect_box.add_child(Ui.label(atk_line, 12, Color(0.85, 0.85, 0.92)))
	inspect_box.add_child(Ui.label("VIT %d" % e.speed, 12, Color(0.85, 0.85, 0.92)))
	var behavior: String = String(e.ai.get("behavior", "melee"))
	inspect_box.add_child(Ui.label(BEHAVIOR_LABEL.get(behavior, behavior), 12, Color(0.7, 0.85, 1.0)))
	var oh: Dictionary = e.ai.get("on_hit", {})
	if not oh.is_empty():
		var sid: String = String(oh.get("id", ""))
		var slabel: String = str(STATUS_LABEL.get(sid, [sid, Color.WHITE])[0])
		inspect_box.add_child(Ui.label("Au contact : %s (%d t)" % [slabel, int(oh.get("turns", 1))], 12, Color(0.9, 0.75, 0.55)))
	var rp: float = float(e.ai.get("resist_phys", 0.0))
	if rp > 0.0:
		inspect_box.add_child(Ui.label("Résiste au physique %d%%" % int(round(rp * 100.0)), 12, Color(0.6, 0.75, 0.9)))
	elif rp < 0.0:
		inspect_box.add_child(Ui.label("Vulnérable au physique", 12, Color(0.9, 0.6, 0.6)))
	var rm: float = float(e.ai.get("resist_magic", 0.0))
	if rm > 0.0:
		inspect_box.add_child(Ui.label("Résiste à la magie %d%%" % int(round(rm * 100.0)), 12, Color(0.6, 0.75, 0.9)))
	elif rm < 0.0:
		inspect_box.add_child(Ui.label("Vulnérable à la magie", 12, Color(0.9, 0.6, 0.6)))
	if e.ai.get("immune_fire", false):
		inspect_box.add_child(Ui.label("Insensible au feu", 12, Color(0.6, 0.75, 0.9)))
	elif float(e.ai.get("weak_fire", 0.0)) > 0.0:
		inspect_box.add_child(Ui.label("Craint le feu", 12, Color(0.9, 0.6, 0.5)))
