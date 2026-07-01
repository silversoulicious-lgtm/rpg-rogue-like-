## Panneau silhouette d'équipement : dessin vectoriel d'Aria avec slots arme /
## armure / relique positionnés autour du corps. Utilisé dans le sidebar HUD.
extends Control

var equipment: Dictionary = {}

# Couleurs reprenant la palette de Data
const BODY_BASE := Color(0.13, 0.11, 0.19)
const BODY_OUT  := Color(0.22, 0.20, 0.32)
const EMPTY_C   := Color(0.35, 0.34, 0.44)
const SLOT_COL  := { "arme": Color(1.0, 0.7, 0.4), "armure": Color(0.6, 0.75, 1.0), "relique": Color(0.5, 1.0, 0.8) }
const SLOT_LBL  := { "arme": "ARME", "armure": "ARMURE", "relique": "RELIQUE" }

func _draw() -> void:
	var cx := size.x * 0.5
	var font := ThemeDB.fallback_font

	# ---- Silhouette Aria (simplifiée, centrée) ----
	# Tête
	draw_circle(Vector2(cx, 22), 15, BODY_OUT)
	draw_circle(Vector2(cx, 22), 13, BODY_BASE)
	# Torse
	draw_rect(Rect2(cx - 20, 37, 40, 56), BODY_OUT)
	draw_rect(Rect2(cx - 18, 39, 36, 52), BODY_BASE)
	# Bras gauche
	draw_rect(Rect2(cx - 34, 41, 14, 40), BODY_OUT)
	draw_rect(Rect2(cx - 32, 43, 10, 36), BODY_BASE)
	# Bras droit
	draw_rect(Rect2(cx + 20, 41, 14, 40), BODY_OUT)
	draw_rect(Rect2(cx + 22, 43, 10, 36), BODY_BASE)
	# Jambe gauche
	draw_rect(Rect2(cx - 20, 93, 17, 52), BODY_OUT)
	draw_rect(Rect2(cx - 18, 95, 13, 48), BODY_BASE)
	# Jambe droite
	draw_rect(Rect2(cx + 3, 93, 17, 52), BODY_OUT)
	draw_rect(Rect2(cx + 5, 95, 13, 48), BODY_BASE)

	# ---- Slots d'équipement ----
	# Armure : centré sur le torse
	_draw_slot(font, "armure", Rect2(cx - 22, 35, 44, 58))
	# Arme : à gauche avec ligne de connexion
	_draw_slot(font, "arme", Rect2(4, 46, 72, 54))
	draw_line(Vector2(76, 70), Vector2(cx - 34, 62), SLOT_COL["arme"].darkened(0.3), 1.0)
	# Relique : à droite avec ligne de connexion
	_draw_slot(font, "relique", Rect2(size.x - 76, 30, 72, 54))
	draw_line(Vector2(size.x - 76, 52), Vector2(cx + 22, 44), SLOT_COL["relique"].darkened(0.3), 1.0)

func _draw_slot(font: Font, slot: String, box: Rect2) -> void:
	var sc: Color = SLOT_COL[slot]
	var has_item: bool = equipment.has(slot)
	# Fond
	draw_rect(box, Color(sc.r * 0.10, sc.g * 0.10, sc.b * 0.14, 0.85), true)
	# Bordure (plus lumineuse si équipé)
	draw_rect(box, sc if has_item else sc.darkened(0.5), false)
	# Libellé de slot
	draw_string(font, box.position + Vector2(4, 13), SLOT_LBL[slot],
		HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 8, 10, sc.darkened(0.1 if has_item else 0.4))
	if has_item:
		var it: Dictionary = equipment[slot]
		var col: Color = it.get("rarity_color", Color.WHITE)
		var nm: String = it.get("name", "?")
		draw_string(font, box.position + Vector2(4, 28), nm,
			HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 8, 11, col)
		# Premier bonus
		var b: Dictionary = it.get("bonus", {})
		if not b.is_empty():
			var k: String = b.keys()[0]
			draw_string(font, box.position + Vector2(4, 42), "+%s %s" % [str(b[k]), k.substr(0, 3)],
				HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 8, 10, col.darkened(0.25))
	else:
		draw_string(font, box.position + Vector2(4, 34), "— vide —",
			HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 8, 11, EMPTY_C)

func refresh(equip: Dictionary) -> void:
	equipment = equip
	queue_redraw()
