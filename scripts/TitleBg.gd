## Fond du menu-titre : silhouette procédurale (tour + Aria) dessinée par code,
## le temps que l'illustration finale (res://assets/title_bg.png) arrive.
## Hud.show_title() charge l'image si elle existe et ne monte ce Control que
## comme repli — dès que le fichier est présent, cette scène n'est plus utilisée.
extends Control

const SKY_STAR := Color(0.85, 0.85, 1.0, 0.55)
# La tour et le sol sont quasi noirs (plus sombres que n'importe quel point du
# dégradé de ciel derrière), pour toujours lire comme silhouette ; c'est le
# liseré (TOWER_EDGE) qui donne sa forme, façon contre-jour de crépuscule.
const TOWER_INK := Color(0.010, 0.012, 0.022)
const TOWER_EDGE := Color(0.58, 0.50, 0.85, 0.9)
const WINDOW_GLOW := Color(1.0, 0.82, 0.45)
const MOON := Color(0.62, 0.58, 0.85, 0.35)
const GROUND := Color(0.008, 0.010, 0.018)
# Aria est nettement plus claire que le sol/la tour pour se détacher en
# silhouette, avec un fin liseré clair (lune) sur un bord.
const ARIA_INK := Color(0.13, 0.11, 0.18)
const ARIA_RIM := Color(0.55, 0.50, 0.80, 0.85)

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
		draw_polyline(PackedVector2Array([pts[0], pts[3]]), TOWER_EDGE, 2.5)
		draw_polyline(PackedVector2Array([pts[1], pts[2]]), TOWER_EDGE, 2.5)
		# Fenêtre éclairée, une sur deux, en alternance de côté.
		if i % 2 == 0:
			var wx: float = cx + (hw0 * 0.4 if i % 4 == 0 else -hw0 * 0.4)
			var wy: float = (y0 + y1) * 0.5
			draw_circle(Vector2(wx, wy), 6.0, Color(WINDOW_GLOW.r, WINDOW_GLOW.g, WINDOW_GLOW.b, 0.30))
			draw_circle(Vector2(wx, wy), 2.6, WINDOW_GLOW)
	# Flèche au sommet.
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - base_w * 0.18, top_y), Vector2(cx + base_w * 0.18, top_y), Vector2(cx, top_y - h * 0.05),
	]), TOWER_INK)

	# Sol / horizon.
	draw_rect(Rect2(0, base_y, w, h - base_y), GROUND)
	draw_line(Vector2(0, base_y), Vector2(w, base_y), TOWER_EDGE, 1.0)

	# Silhouette d'Aria : figure au pied de la tour, tournée vers elle. Un peu
	# de lumière au sol sous ses pieds (clair de lune) pour attirer l'œil et
	# la détacher nettement du sol, plus clair qu'elle mais aussi très sombre.
	var ax: float = w * 0.40
	var ay: float = base_y
	draw_circle(Vector2(ax, ay - h * 0.006), h * 0.05, Color(ARIA_RIM.r, ARIA_RIM.g, ARIA_RIM.b, 0.10))
	draw_circle(Vector2(ax, ay - h * 0.11), h * 0.026, ARIA_INK)                  # tête
	draw_circle(Vector2(ax, ay - h * 0.11), h * 0.026, ARIA_RIM, false, 1.5)      # liseré (lune)
	var body := PackedVector2Array([
		Vector2(ax - h * 0.020, ay - h * 0.085), Vector2(ax + h * 0.020, ay - h * 0.085),
		Vector2(ax + h * 0.028, ay), Vector2(ax - h * 0.028, ay),
	])
	draw_colored_polygon(body, ARIA_INK)
	draw_polyline(PackedVector2Array([
		Vector2(ax - h * 0.020, ay - h * 0.085), Vector2(ax - h * 0.028, ay),
	]), ARIA_RIM, 1.5)
