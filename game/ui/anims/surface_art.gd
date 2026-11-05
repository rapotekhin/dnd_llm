class_name SurfaceArt
extends RefCounted
## The squares of a zone drawn as simple sprites (v0.8.4.30, the author's feedback): a look of AnimRules.surface — flames
## that flicker, a web, spikes, beads, a glossy puddle, vines, haze, the dark, frost, a glow, a ripple, bubbles. A look's
## `texture` replaces the stub with its picture; nothing here knows a spell.

static var _textures: Dictionary = {}


static func draw(ci: CanvasItem, box: Rect2, look: Dictionary, time: float, cell: Vector2i) -> void:
	var tex := str(look.get("texture", ""))
	if not tex.is_empty() and ResourceLoader.exists(tex):
		if not _textures.has(tex):
			_textures[tex] = load(tex)
		ci.draw_texture_rect(_textures[tex], box, false)
		return
	var col := Color(str(look.get("colour", "#ffffff")))
	var seed := float((cell.x * 73856093) ^ (cell.y * 19349663)) * 0.0001
	var t := box.size.x
	var c := box.get_center()
	match str(look.get("kind", "")):
		"flames":
			for i in 3:
				var x := box.position.x + t * (0.22 + 0.28 * i)
				var h := t * (0.45 + 0.18 * sin(time * 7.0 + seed + i * 2.1))
				var base := box.end.y - t * 0.08
				var w := t * 0.16
				ci.draw_colored_polygon(PackedVector2Array([Vector2(x - w, base), Vector2(x, base - h), Vector2(x + w, base)]), Color(col, 0.85))
				ci.draw_colored_polygon(PackedVector2Array([Vector2(x - w * 0.5, base), Vector2(x, base - h * 0.55), Vector2(x + w * 0.5, base)]), Color(1, 0.9, 0.45, 0.9))
		"web":
			var p := box.grow(-t * 0.06)
			for a: Array in [[p.position, p.end], [Vector2(p.end.x, p.position.y), Vector2(p.position.x, p.end.y)], [Vector2(c.x, p.position.y), Vector2(c.x, p.end.y)], [Vector2(p.position.x, c.y), Vector2(p.end.x, c.y)]]:
				ci.draw_line(a[0], a[1], Color(col, 0.6), 1.0)
			for r: float in [0.18, 0.34]:
				ci.draw_arc(c, t * r, 0.0, TAU, 8, Color(col, 0.55), 1.0)
		"spikes":
			for i in 4:
				var o := Vector2(t * (0.25 + 0.5 * (i % 2)), t * (0.3 + 0.45 * int(i / 2.0)))
				var at := box.position + o
				ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-t * 0.08, t * 0.07), at + Vector2(0, -t * 0.11), at + Vector2(t * 0.08, t * 0.07)]), Color(col, 0.9))
		"beads":
			for i in 5:
				var o := Vector2(fposmod(seed * 13.0 + i * 0.37, 1.0), fposmod(seed * 7.0 + i * 0.61, 1.0)) * 0.7 + Vector2(0.15, 0.15)
				ci.draw_circle(box.position + o * t, t * 0.06, Color(col, 0.9))
		"gloss":
			ci.draw_arc(c + Vector2(-t * 0.1, -t * 0.1), t * 0.22, PI * 1.05, PI * 1.6, 8, Color(col, 0.55), maxf(1.5, t * 0.05))
		"vines":
			for k in 2:
				var pts := PackedVector2Array()
				for i in 7:
					var y := box.position.y + t * (0.1 + 0.8 * i / 6.0)
					pts.append(Vector2(box.position.x + t * (0.3 + 0.4 * k) + sin(i * 1.3 + seed + k) * t * 0.1, y))
				ci.draw_polyline(pts, Color(col, 0.85), maxf(1.5, t * 0.05))
		"haze":
			for i in 3:
				var o := Vector2(sin(time * 0.6 + seed + i * 2.0), cos(time * 0.5 + seed + i * 1.7)) * t * 0.15
				ci.draw_circle(c + o + Vector2(t * (i - 1) * 0.2, 0), t * 0.24, Color(col, 0.16))
		"dark":
			ci.draw_rect(box, Color(col, 0.55))
		"frost":
			for a in 3:
				var d := Vector2.from_angle(a * PI / 3.0) * t * 0.22
				ci.draw_line(c - d, c + d, Color(col, 0.8), maxf(1.0, t * 0.035))
		"glow":
			var pulse := 0.5 + 0.5 * sin(time * 3.0 + seed)
			ci.draw_rect(box.grow(-t * 0.08), Color(col, 0.18 + 0.2 * pulse), false, maxf(1.5, t * 0.05))
		"ripple":
			var r := fposmod(time * 0.6 + seed, 1.0)
			ci.draw_arc(c, t * (0.1 + 0.35 * r), 0.0, TAU, 16, Color(col, 0.6 * (1.0 - r)), maxf(1.0, t * 0.04))
		"bubbles":
			for i in 3:
				var rise := fposmod(time * 0.4 + seed + i * 0.33, 1.0)
				ci.draw_arc(Vector2(box.position.x + t * (0.25 + 0.25 * i), box.end.y - t * (0.15 + 0.7 * rise)), t * 0.07, 0.0, TAU, 8, Color(col, 0.8 * (1.0 - rise)), 1.5)
