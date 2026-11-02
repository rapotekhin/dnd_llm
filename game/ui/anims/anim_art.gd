class_name AnimArt
extends RefCounted
## What a token and a strike draw alike (v0.8.4.23): one cache of the rows' textures and one weapon, so a sword on the token and
## the same sword in its swing are one picture — the row's `texture` of `data/anims.json`, else a stub of its length and head.

static var _cache := {}


## The texture at `path`, null without one; loaded once for the whole fight.
static func texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


## A weapon of `sprite` held at `base` and pointed at `angle`, `t` a square; no sprite — a fist. `lib` is data/anims.json or a
## context that carries its `sprites` and `palette`.
static func weapon(ci: CanvasItem, lib: Dictionary, sprite: String, base: Vector2, angle: float, t: float) -> void:
	var pal: Dictionary = lib.get("palette", {})
	var steel := Color(str(pal.get("steel", "#cfd6de")))
	var wood := Color(str(pal.get("wood", "#8a6a42")))
	var w := maxf(2.0, t * 0.07)
	var dir := Vector2.RIGHT.rotated(angle)
	if sprite.is_empty():
		ci.draw_circle(base + dir * t * 0.3, t * 0.11, Color(str(pal.get("fist", "#f2cca6"))))
		return
	var row: Dictionary = lib.get("sprites", {}).get(sprite, {})
	var length := float(row.get("len", 0.4)) * t
	var tip := base + dir * length
	var tex := texture(str(row.get("texture", "")))
	if tex != null:
		ci.draw_set_transform(base + dir * length / 2.0, angle + PI * 0.5, Vector2.ONE * length / maxf(1.0, float(tex.get_height())))
		ci.draw_texture(tex, -tex.get_size() / 2.0)
		ci.draw_set_transform(Vector2.ZERO)
		return
	var across := dir.orthogonal()
	match str(row.get("head", "")):
		"bow":
			ci.draw_arc((base + tip) / 2.0, length / 2.0, angle, angle + PI, 12, wood, w, true)
		"cross":
			ci.draw_line(base, tip, wood, w)
			ci.draw_line(tip - across * length * 0.3, tip + across * length * 0.3, wood, w)
		"axe":
			ci.draw_line(base, tip, wood, w)
			var a := length * 0.25
			ci.draw_colored_polygon(PackedVector2Array([tip, tip + across * a, tip + across * a - dir * a, tip - dir * a]), steel)
		"knob":
			ci.draw_line(base, tip, wood, w)
			ci.draw_circle(tip, length * 0.14, steel)
		"tip":
			ci.draw_line(base, tip, wood, w)
			ci.draw_line(tip, tip + dir * length * 0.18, steel, w * 1.6)
		"curl":
			ci.draw_line(base, base + dir * length * 0.3, wood, w)
			ci.draw_arc(tip, length * 0.3, angle, angle + PI * 1.5, 12, wood, w * 0.6, true)
		"pouch":
			ci.draw_line(base, tip, wood, w * 0.5)
			ci.draw_circle(tip, length * 0.15, wood)
		_:
			ci.draw_line(base, tip, steel, w)
			var guard := base + dir * length * 0.2
			ci.draw_line(guard - across * length * 0.18, guard + across * length * 0.18, wood, w)
