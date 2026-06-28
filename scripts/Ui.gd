## Fabrique de widgets : centralise la création des Label/Button/styles
## pour éviter le boilerplate répété (add_theme_*_override partout).
class_name Ui
extends RefCounted

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

static func button(text: String = "", min_h: float = 0.0, size: int = 0) -> Button:
	var b := Button.new()
	b.text = text
	if size > 0:
		b.add_theme_font_size_override("font_size", size)
	if min_h > 0.0:
		b.custom_minimum_size = Vector2(0, min_h)
	return b

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
