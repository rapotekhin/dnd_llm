class_name StubAnim
extends FightAnim
## The stubs of v0.8.4.23: each phase of a kind is drawn by its `stub` in lines and circles. A phase whose name is an animation of
## the kind's `frames` (a SpriteFrames of `data/anims.json`) plays that instead, placed and moved as the stub would be; the other
## phases stay stubs. So a kind is replaced phase by phase, or whole by a `scene`, and this file is never touched for it.

var _stub := ""
var _at := "to"
var _k := 0.0  ## the progress of the phase, 0…1
var _frozen := false


func play(c: Dictionary) -> void:
	ctx = c
	for p: Dictionary in c["phases"]:
		var frames: SpriteFrames = c.get("frames")
		if frames != null and frames.has_animation(str(p["phase"])):
			await _sprite(frames, p)
		else:
			await _phase(p)
	finished.emit()


## A still of one phase at `k`: the playtest's screenshot of a kind mid-way.
func hold(c: Dictionary, phase: int, k: float) -> void:
	ctx = c
	_frozen = true
	var p: Dictionary = c["phases"][clampi(phase, 0, (c["phases"] as Array).size() - 1)]
	_stub = str(p["stub"])
	_at = str(p["at"])
	_k = k
	queue_redraw()


func _phase(p: Dictionary) -> void:
	_stub = str(p["stub"])
	_at = str(p["at"])
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		_k = v
		queue_redraw(), 0.0, 1.0, seconds(p))
	await tw.finished


## A phase of the kind's own frames: on its point, or flown along the path.
func _sprite(frames: SpriteFrames, p: Dictionary) -> void:
	var sp := AnimatedSprite2D.new()
	sp.sprite_frames = frames
	add_child(sp)
	var tex := frames.get_frame_texture(str(p["phase"]), 0)
	if tex != null:
		sp.scale = Vector2.ONE * float(ctx["tile"]) / maxf(1.0, maxf(tex.get_width(), tex.get_height()))
	sp.play(str(p["phase"]))
	var from := point("by") if str(p["at"]) == "path" else point(str(p["at"]))
	var to := point("to") if str(p["at"]) == "path" else from
	sp.position = from
	sp.rotation = (to - from).angle() if to != from else 0.0
	var tw := create_tween()
	tw.tween_property(sp, "position", to, seconds(p))
	await tw.finished
	sp.queue_free()


func _draw() -> void:
	if _stub.is_empty():
		return
	var t := float(ctx["tile"])
	var col: Color = ctx["colour"]
	var from: Vector2 = ctx["from"]
	var to: Vector2 = ctx["to"]
	var here := point(_at)
	var k := _k
	var fade := 1.0 - k
	var dir := (to - from).normalized() if to != from else Vector2.RIGHT
	var w := maxf(2.0, t * 0.08)
	match _stub:
		"glow":
			draw_circle(here, t * (0.2 + 0.25 * k), Color(col, 0.3 * fade))
			draw_arc(here, t * (0.25 + 0.3 * k), 0.0, TAU, 32, Color(col, fade), w, true)
		"ball":
			var n := maxi(1, int(ctx.get("n", 1)))
			for i in n:
				var ki := clampf(k * (1.0 + 0.2 * (n - 1)) - 0.2 * i, 0.0, 1.0)
				var at := from.lerp(to, ki)
				draw_line(from.lerp(to, maxf(0.0, ki - 0.15)), at, Color(col, 0.5), w)
				draw_circle(at, t * 0.13, col)
		"flash":
			draw_circle(here, t * (0.2 + 0.4 * k), Color(col, 0.7 * fade))
			draw_arc(here, t * (0.25 + 0.45 * k), 0.0, TAU, 32, Color(Color.WHITE, fade), w * 0.6, true)
		"fade":
			draw_circle(here, t * 0.15 * fade + 1.0, Color(col, 0.6 * fade))
		"ray":
			draw_line(from, to, Color(col, 0.35), w * 3.0)
			draw_line(from, to, col.lightened(0.4), w * (1.2 + 0.6 * sin(k * TAU * 2.0)))
		"ray_fade":
			draw_line(from, to, Color(col, 0.6 * fade), w * 1.5 * fade + 1.0)
		"cells_flash":
			for c: Vector2 in _cells():
				draw_rect(Rect2(c - Vector2(t, t) / 2.0, Vector2(t, t)), Color(col, 0.6 * minf(1.0, k * 3.0)))
		"cells_fade":
			for c: Vector2 in _cells():
				draw_rect(Rect2(c - Vector2(t, t) / 2.0, Vector2(t, t)), Color(col, 0.6 * fade))
		"wave":
			var cells := _cells()
			var far := 1.0
			for c: Vector2 in cells:
				far = maxf(far, c.distance_to(from))
			for c: Vector2 in cells:
				var d := c.distance_to(from) / far
				if d <= k:
					draw_rect(Rect2(c - Vector2(t, t) / 2.0, Vector2(t, t)), Color(col, 0.65 * (1.0 - (k - d))))
		"ring_out":
			var r := t * 0.4
			for c: Vector2 in ctx.get("cells", []):
				r = maxf(r, (c as Vector2).distance_to(from) + t * 0.5)
			r = maxf(r, t * 1.5)
			draw_arc(from, t * 0.4 + (r - t * 0.4) * k, 0.0, TAU, 48, Color(col, fade), w * 1.5, true)
			draw_circle(from, t * 0.4 + (r - t * 0.4) * k, Color(col, 0.15 * fade))
		"lunge":
			var at := from.lerp(to, 0.75 * sin(PI * k))
			draw_circle(at, t * 0.14, col.lightened(0.2))
			draw_arc(at, t * 0.14, 0.0, TAU, 20, Color.BLACK, 1.5, true)
			if k > 0.4 and k < 0.8:
				_spark(to.lerp(from, 0.3), t, col)
		"sigil":
			var rise := -1.0 if str(ctx.get("result", "")) != "debuff" else 1.0
			var at := here + Vector2(0.0, -t * 0.7 + rise * t * 0.3 * k)
			var a := sin(PI * k)
			var s := t * 0.22
			var pts := PackedVector2Array([at + Vector2(0, -s), at + Vector2(s, 0), at + Vector2(0, s), at + Vector2(-s, 0), at + Vector2(0, -s)])
			draw_polyline(pts, Color(col, a), w, true)
			draw_circle(at, s * 0.3, Color(col, a))
		"ring_pulse":
			draw_arc(from, t * (0.5 + 0.08 * sin(k * TAU * 2.0)), 0.0, TAU, 40, Color(col, 1.0 - 0.7 * k), w * 1.3, true)
			draw_circle(from, t * 0.5, Color(col, 0.18 * fade))
		"puff":
			for i in 3:
				var off := Vector2(cos(i * TAU / 3.0), sin(i * TAU / 3.0)) * t * 0.2 * (1.0 + k)
				draw_circle(here + off, t * (0.2 + 0.2 * k), Color(col.lerp(Color.WHITE, 0.5), 0.55 * fade))
		"star":
			draw_circle(here, t * (0.3 + 0.3 * k), Color(col, 0.6 * fade))
			for i in 8:
				var v := Vector2.RIGHT.rotated(i * TAU / 8.0)
				draw_line(here + v * t * 0.2, here + v * t * (0.35 + 0.45 * k), Color(Color.WHITE, fade), w)
		"sparks_up":
			for i in 6:
				var x := (i - 2.5) * t * 0.12
				draw_circle(here + Vector2(x, t * 0.2 - k * t * (0.6 + 0.1 * (i % 3))), t * 0.06, Color(col, fade))
		"ring_in":
			draw_arc(here, t * (0.95 - 0.5 * k), 0.0, TAU, 40, Color(col, 0.3 + 0.7 * k), w * 1.4, true)
		"bubble":
			draw_circle(here, t * 0.55, Color(col.lerp(Color.WHITE, 0.6), 0.25 * fade))
			draw_arc(here, t * 0.55, 0.0, TAU, 40, Color(Color.WHITE, fade), w, true)
		"arc":
			_weapon(from + dir * t * 0.15, dir.angle() - 1.0 + 2.0 * k, t)
			draw_arc(from, t * 0.75, dir.angle() - 1.0, dir.angle() - 1.0 + 2.0 * k, 16, Color(col, 0.4), w, true)
		"thrust":
			_weapon(from + dir * t * (0.1 + 0.55 * sin(PI * k)), dir.angle(), t)
		"raise":
			_weapon(from + dir * t * 0.15, dir.angle() - 1.3 * k, t)
		"smash":
			_weapon(from + dir * t * 0.15, dir.angle() - 1.3 + 1.4 * k, t)
			if k > 0.8:
				_spark(to.lerp(from, 0.35), t, col)
		"draw":
			_weapon(from, dir.angle(), t)
			draw_line(from, from - dir * t * 0.25 * k, Color(Color.WHITE, 0.8), 1.5)
		"stick":
			_projectile(from.lerp(to, k), dir, t)
		"stray":
			var end: Vector2 = ctx["beside"]
			_projectile(from.lerp(end, k), (end - from).normalized(), t)
		"spin":
			var at := from.lerp(to, k)
			if str(ctx.get("sprite", "")).is_empty():
				draw_circle(at, t * 0.12, col)
			else:
				_weapon(at, k * TAU * 2.0, t * 0.7)
		"jaws":
			var gap := t * 0.3 * fade
			draw_arc(to + Vector2(0, -gap), t * 0.35, PI * 0.15, PI * 0.85, 16, Color.WHITE, w * 1.4, true)
			draw_arc(to + Vector2(0, gap), t * 0.35, PI * 1.15, PI * 1.85, 16, Color.WHITE, w * 1.4, true)
			for i in 3:
				var x := (i - 1) * t * 0.15
				draw_line(to + Vector2(x, -gap - t * 0.05), to + Vector2(x, -gap + t * 0.08), Color.WHITE, w * 0.7)
		"claws":
			for i in 3:
				var off := Vector2((i - 1) * t * 0.18, 0)
				var a := to + off + Vector2(-t * 0.3, -t * 0.35)
				var b := to + off + Vector2(t * 0.3, t * 0.35)
				draw_line(a, a.lerp(b, clampf(k * 1.4 - 0.15 * i, 0.0, 1.0)), Color(Color.WHITE, 0.95), w)
		"sidestep":
			var side := Vector2(-dir.y, dir.x) * t * 0.4 * sin(PI * k)
			draw_arc(to + side, t * 0.4, 0.0, TAU, 32, Color(Color.WHITE, 0.8), w, true)
			draw_line(to, to + side, Color(Color.WHITE, 0.4), w * 2.0)
		"shield_turn":
			var face := (from - to).normalized()
			var mid := to + face * t * 0.4
			var across := Vector2(-face.y, face.x) * t * 0.3 * (0.6 + 0.4 * minf(1.0, k * 2.0))
			draw_line(mid - across, mid + across, _art_colour("shield"), w * 2.2)
			if k > 0.3:
				_spark(mid, t, Color.WHITE)
		"parry":
			var face := (from - to).normalized()
			var mid := to + face * t * 0.45
			var perp := Vector2(-face.y, face.x)
			draw_line(mid - perp * t * 0.35 - face * t * 0.1, mid + perp * t * 0.35 + face * t * 0.1, _art_colour("steel"), w)
			draw_line(mid - perp * t * 0.35 + face * t * 0.1, mid + perp * t * 0.35 - face * t * 0.1, _art_colour("steel"), w)
			if k > 0.3:
				_spark(mid, t, Color.WHITE)
		"slide":
			_ghost(from.lerp(to, k), t)
		"hop":
			var at := from.lerp(to, k)
			draw_circle(at, t * 0.3, Color(0, 0, 0, 0.25))
			_ghost(at + Vector2(0, -sin(PI * k) * t * 0.7), t)
		"tether":
			draw_line(from, to, Color(col, 0.8), w)
			_ghost(to.lerp(from, 0.3 * k), t)
		"tip":
			_squash(here, t, 1.0 - 0.6 * k)
		"untip":
			_squash(here, t, 0.4 + 0.6 * k)
		"fade_out":
			draw_circle(here, t * (0.4 + 0.3 * k), Color(0.6, 0.6, 0.65, 0.5 * sin(PI * k)))
		"bottle":
			var at := here + Vector2(t * 0.35, t * 0.3).lerp(Vector2(0, -t * 0.1), k)
			draw_rect(Rect2(at - Vector2(t * 0.07, t * 0.12), Vector2(t * 0.14, t * 0.24)), Color(0.5, 0.9, 0.6, fade + 0.2))
		"speech":
			var box := Rect2(here + Vector2(-t * 0.4, -t * 1.15), Vector2(t * 0.8, t * 0.45))
			draw_rect(box, Color(1, 1, 1, 0.85 * sin(PI * k)))
			for i in 3:
				draw_circle(box.get_center() + Vector2((i - 1) * t * 0.18, 0), t * 0.04, Color(0, 0, 0, sin(PI * k)))
		"flip":
			_weapon(here, -PI * 0.5 + PI * k, t)


func _cells() -> Array[Vector2]:
	var out: Array[Vector2] = []
	out.assign(ctx.get("cells", []))
	if out.is_empty():  # an area with no squares told: a wedge of three toward the target
		var from: Vector2 = ctx["from"]
		var to: Vector2 = ctx["to"]
		var t := float(ctx["tile"])
		for i in range(1, 4):
			out.append(from + (to - from).normalized() * t * i)
	return out


## The weapon in the hand: its art if the row has one, else a stick of its length with a head.
func _weapon(at: Vector2, angle: float, t: float) -> void:
	var sprite := str(ctx.get("sprite", ""))
	var art: Dictionary = ctx.get("art", {})
	if art.has(sprite):
		var tex: Texture2D = art[sprite]
		draw_set_transform(at, angle + PI * 0.5, Vector2.ONE * t / maxf(1.0, float(tex.get_height())))
		draw_texture(tex, -tex.get_size() / 2.0)
		draw_set_transform(Vector2.ZERO)
		return
	var row: Dictionary = ctx.get("sprites", {}).get(sprite, {"len": 0.25})
	var tip := at + Vector2.RIGHT.rotated(angle) * t * float(row.get("len", 0.25)) * 1.2
	draw_line(at, tip, _art_colour("steel"), maxf(2.0, t * 0.07))
	if sprite.is_empty():
		draw_circle(tip, t * 0.11, Color(0.95, 0.8, 0.65))  # a fist


func _projectile(at: Vector2, dir: Vector2, t: float) -> void:
	var proj := str(ctx.get("proj", ""))
	var art: Dictionary = ctx.get("art", {})
	if art.has(proj):
		var tex: Texture2D = art[proj]
		draw_set_transform(at, dir.angle(), Vector2.ONE * t * 0.5 / maxf(1.0, float(tex.get_width())))
		draw_texture(tex, -tex.get_size() / 2.0)
		draw_set_transform(Vector2.ZERO)
		return
	var length := float(ctx.get("projectiles", {}).get(proj, {}).get("len", 0.4)) * t
	if length <= 0.0:
		draw_circle(at, t * 0.08, Color(0.7, 0.7, 0.7))  # a stone
	else:
		draw_line(at - dir * length, at, _art_colour("wood"), maxf(2.0, t * 0.05))
		draw_line(at - dir * t * 0.06, at, _art_colour("steel"), maxf(2.0, t * 0.08))


func _spark(at: Vector2, t: float, col: Color) -> void:
	for i in 4:
		var v := Vector2.RIGHT.rotated(i * TAU / 4.0 + PI / 4.0)
		draw_line(at + v * t * 0.05, at + v * t * 0.2, col.lightened(0.5), 2.0)


func _ghost(at: Vector2, t: float) -> void:
	draw_arc(at, t * 0.4, 0.0, TAU, 32, Color(Color.WHITE, 0.85), maxf(2.0, t * 0.07), true)


func _squash(at: Vector2, t: float, tall: float) -> void:
	draw_set_transform(at, 0.0, Vector2(1.0, tall))
	draw_arc(Vector2.ZERO, t * 0.4, 0.0, TAU, 32, Color(Color.WHITE, 0.85), maxf(2.0, t * 0.07), true)
	draw_set_transform(Vector2.ZERO)


func _art_colour(key: String) -> Color:
	return Color(str(ctx.get("palette", {}).get(key, "#cccccc")))
