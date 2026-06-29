## Fabrique de widgets : centralise la création des Label/Button/styles
## pour éviter le boilerplate répété (add_theme_*_override partout).
## Inclut la charte visuelle des écrans de menu (boutons stylés, fond dégradé,
## cartes) pour une présentation homogène et soignée.
class_name Ui
extends RefCounted

# --- Palette de la charte « Les Strates » -------------------------------------
const ACCENT := Color(0.62, 0.52, 1.0)        # violet mystique (identité)
const ACCENT_SOFT := Color(0.72, 0.62, 1.0)
const GOLD := Color(1.0, 0.85, 0.35)
const INK := Color(0.92, 0.92, 0.98)
const MUTED := Color(0.62, 0.62, 0.72)

static func label(text: String = "", size: int = 14, color: Color = Color.WHITE,
		center: bool = false, wrap: bool = false, min_w: float = 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if min_w > 0.0:
		l.custom_minimum_size = Vector2(min_w, 0)
	return l

## Bouton standard, désormais habillé d'un StyleBox à états (normal/survol/
## pressé/désactivé) pour un rendu cohérent et « fini » dans tout le jeu.
static func button(text: String = "", min_h: float = 0.0, size: int = 0, min_w: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	if size > 0:
		b.add_theme_font_size_override("font_size", size)
	var mw: float = min_w
	var mh: float = min_h
	if mw > 0.0 or mh > 0.0:
		b.custom_minimum_size = Vector2(mw, mh)
	_style_button(b)
	return b

## Bouton de menu : large, généreux, pour les écrans de lancement.
static func menu_button(text: String = "", width: float = 420.0, font: int = 18) -> Button:
	var b := button(text, 50.0, font, width)
	return b

static func _style_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _btn_box(Color(0.16, 0.14, 0.22), Color(0.34, 0.30, 0.50)))
	b.add_theme_stylebox_override("hover", _btn_box(Color(0.25, 0.21, 0.36), ACCENT))
	b.add_theme_stylebox_override("pressed", _btn_box(Color(0.12, 0.10, 0.18), ACCENT_SOFT))
	b.add_theme_stylebox_override("disabled", _btn_box(Color(0.10, 0.09, 0.13), Color(0.18, 0.16, 0.22)))
	b.add_theme_stylebox_override("focus", _btn_box(Color(0.25, 0.21, 0.36), ACCENT))
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", ACCENT_SOFT)
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.43, 0.50))

static func _btn_box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(6)
	s.set_border_width_all(1)
	s.border_color = border
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s

static func vbox(separation: int = 6) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", separation)
	return b

static func panel_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(8)
	s.set_content_margin_all(14)
	return s

## Style de « carte » (sélection de héros, panneaux d'écran) : fond + liseré.
static func card_style(bg: Color, border: Color, radius: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(2)
	s.border_color = border
	s.set_content_margin_all(18)
	return s

static func bar_style(bg: Color, radius: int = 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	return s

static func progress_bar(height: int, fill: Color, back: Color, radius: int = 4) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_stylebox_override("fill", bar_style(fill, radius))
	b.add_theme_stylebox_override("background", bar_style(back, radius))
	return b

## Petite barre de stat (libellé + jauge remplie selon value/max) pour les fiches.
static func stat_gauge(name: String, value: int, vmax: int, fill: Color, width: float = 200.0) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := label(name, 13, MUTED)
	lbl.custom_minimum_size = Vector2(70, 0)
	row.add_child(lbl)
	var bar := progress_bar(14, fill, Color(0.12, 0.11, 0.16), 3)
	bar.custom_minimum_size = Vector2(width, 14)
	bar.max_value = max(1, vmax)
	bar.value = clampi(value, 0, vmax)
	row.add_child(bar)
	var val := label(str(value), 13, INK)
	val.custom_minimum_size = Vector2(34, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	return row

## Fond plein écran en dégradé vertical (procédural, sans fichier d'asset).
static func gradient_bg(top: Color, bottom: Color) -> TextureRect:
	var grad := Gradient.new()
	grad.set_color(0, top)
	grad.set_color(1, bottom)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 8
	tex.height = 256
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect
