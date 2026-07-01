## Fond du menu-titre : silhouette procédurale (tour + Aria) dessinée par code,
## le temps que l'illustration finale (res://assets/title_bg.png) arrive.
## Hud.show_title() charge l'image si elle existe et ne monte ce Control que
## comme repli — dès que le fichier est présent, cette scène n'est plus utilisée.
extends Control

const SKY_STAR := Color(0.85, 0.85, 1.0, 0.55)
const TOWER_INK := Color(0.05, 0.045, 0.09)
const TOWER_EDGE := Color(0.16, 0.13, 0.24)
const WINDOW_GLOW := Color(1.0, 0.82, 0.45)
const MOON := Color(0.62, 0.58, 0.85, 0.35)
const ARIA_INK := Color(0.03, 0.03, 0.06)
const GROUND := Color(0.03, 0.035, 0.05)

# Positions d'étoiles fixes (proportions 0..1 de la taille du Control) : pas
# besoin d'aléatoire ici, un motif décoratif stable suffit.
const STARS := [
	Vector2(0.08, 0.10), Vector2(0.15, 0.22), Vector2(0.22, 0.08), Vector2(0.30, 0.16),
	Vector2(0.38, 0.06), Vector2(0.45, 0.20), Vector2(0.52, 0.10), Vector2(0.60, 0.05),
	Vector2(0.68, 0.14), Vector2(0.10, 0.30), Vector2(0.34, 0.28), Vector2(0.05, 0.18),
]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# _draw() dépend de `size` (ancré en PRESET_FULL_RECT) : si le premier appel
	# survient avant que les ancres n'aient fini de résoudre la taille réelle,
	# ce signal garantit un redessin dès que `size` se stabilise.
	resized.connect(queue_redraw)

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return

	for s in STARS:
		draw_circle(Vector2(s.x * w, s.y * h), 1.4, SKY_STAR)

	# Lune / halo mystique au-dessus de la tour.
	var moon_c := Vector2(w * 0.78, h * 0.22)
	draw_circle(moon_c, h * 0.10, MOON)
	draw_circle(moon_c, h * 0.055, Color(MOON.r, MOON.g, MOON.b, 0.6))

	# Tour : empilement de trapèzes qui s'affinent vers le haut, décalés à droite
	# pour laisser la place au bloc de menu (ancré en bas à droite) sans se
	# chevaucher avec le pied de la tour où se tient Aria.
	var cx: float = w * 0.74
	var base_w: float = w * 0.16
	var top_y: float = h * 0.12
	var base_y: float = h * 0.86
	var segments := 6
	for i in segments:
		var t0: float = float(i) / float(segments)
		var t1: float = float(i + 1) / float(segments)
		var y0: float = lerp(base_y, top_y, t0)
		var y1: float = lerp(base_y, top_y, t1)
		var hw0: float = lerp(base_w, base_w * 0.35, t0) * 0.5
		var hw1: float = lerp(base_w, base_w * 0.35, t1) * 0.5
		var pts := PackedVector2Array([
			Vector2(cx - hw0, y0), Vector2(cx + hw0, y0),
			Vector2(cx + hw1, y1), Vector2(cx - hw1, y1),
		])
		draw_colored_polygon(pts, TOWER_INK)
		draw_polyline(PackedVector2Array([pts[0], pts[3]]), TOWER_EDGE, 1.5)
		draw_polyline(PackedVector2Array([pts[1], pts[2]]), TOWER_EDGE, 1.5)
		# Fenêtre éclairée, une sur deux, en alternance de côté.
		if i % 2 == 0:
			var wx: float = cx + (hw0 * 0.4 if i % 4 == 0 else -hw0 * 0.4)
			var wy: float = (y0 + y1) * 0.5
			draw_circle(Vector2(wx, wy), 3.5, Color(WINDOW_GLOW.r, WINDOW_GLOW.g, WINDOW_GLOW.b, 0.25))
			draw_circle(Vector2(wx, wy), 1.6, WINDOW_GLOW)
	# Flèche au sommet.
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - base_w * 0.18, top_y), Vector2(cx + base_w * 0.18, top_y), Vector2(cx, top_y - h * 0.05),
	]), TOWER_INK)

	# Sol / horizon.
	draw_rect(Rect2(0, base_y, w, h - base_y), GROUND)
	draw_line(Vector2(0, base_y), Vector2(w, base_y), TOWER_EDGE, 1.0)

	# Silhouette d'Aria : petite figure au pied de la tour, tournée vers elle.
	var ax: float = w * 0.40
	var ay: float = base_y
	draw_circle(Vector2(ax, ay - h * 0.075), h * 0.018, ARIA_INK)                 # tête
	var body := PackedVector2Array([
		Vector2(ax - h * 0.012, ay - h * 0.058), Vector2(ax + h * 0.012, ay - h * 0.058),
		Vector2(ax + h * 0.017, ay), Vector2(ax - h * 0.017, ay),
	])
	draw_colored_polygon(body, ARIA_INK)
