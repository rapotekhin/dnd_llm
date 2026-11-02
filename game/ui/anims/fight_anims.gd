class_name FightAnims
extends Node2D
## The player of a fight's animations on the map (v0.8.4.23): takes the engine's events (AnimRules.take) and plays them one by
## one over the map field — the strike, then its outcome or the look of the miss; the outcomes of one area at once. Which kind
## an event is the engine said; how a kind looks is its row of `data/anims.json`: a `scene` (a FightAnim of its own), else the
## stubs of StubAnim with the row's `frames` over the phases they name. Weapons, projectiles and a shield take their row's
## `texture` when there is one. The speed is the fight's («Скорость боя»); «Сразу» shows none.

const NORMAL_DELAY := 0.6  ## SaveManager's normal pause: the phases' times are at it

var field: MapField
var lib: Dictionary = {}  ## data/anims.json
var speed := 1.0  ## × of the phases' time; 0 — nothing is played
var _queue: Array = []
var _busy := false
var _art := {}  ## texture by sprite or projectile id, loaded once
var _scenes := {}
var _frames := {}


func setup(map_field: MapField, anims: Dictionary) -> void:
	field = map_field
	lib = anims
	_art.clear()
	for group: String in ["sprites", "projectiles"]:
		for id: String in lib.get(group, {}):
			var path := str(lib[group][id].get("texture", ""))
			if not path.is_empty() and ResourceLoader.exists(path):
				_art[id] = load(path)


func play(events: Array) -> void:
	if speed <= 0.0 or field == null:
		return
	_queue.append_array(_steps(events))
	if not _busy:
		_run()


func clear() -> void:
	_queue.clear()
	for c: Node in get_children():
		c.queue_free()


## The events as steps: each a list of contexts played together.
func _steps(events: Array) -> Array:
	var out: Array = []
	var outcomes: Array = []
	for e: Dictionary in events:
		if str(e.get("act")) == "outcome":
			var c := context(e, str(e["anim"]))
			if not c.is_empty():
				outcomes.append(c)
			continue
		if not outcomes.is_empty():
			out.append(outcomes)
			outcomes = []
		for c: Dictionary in _chain(e):
			out.append([c])
	if not outcomes.is_empty():
		out.append(outcomes)
	return out


## One event as the kinds it plays in order: the strike or the cast, then what came of it.
func _chain(e: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var main := context(e, str(e["anim"]))
	if main.is_empty():
		return out
	var res := str(e.get("result", ""))
	var miss := str(e.get("miss", ""))
	if bool(e.get("again", false)):  # the next dart or ray: no windup
		main["phases"] = (main["phases"] as Array).filter(func(p: Dictionary) -> bool: return str(p["phase"]) != "windup")
	if res == "miss" and miss in ["overshoot", "undershoot"]:  # the shot never reaches: it flies past or falls short
		main["phases"] = (main["phases"] as Array).filter(func(p: Dictionary) -> bool: return str(p["phase"]) == "windup")
	elif res == "miss" and str(e["anim"]) == "beam":
		main["to"] = main["beside"]  # a ray goes by
	if not (main["phases"] as Array).is_empty():
		out.append(main)
	if res == "miss" and not miss.is_empty():
		out.append(context(e, miss))
	elif res in ["hit", "crit"] and e.has("to") and str(lib["kinds"].get(str(e["anim"]), {}).get("group", "")) in ["strike", "spell"]:
		out.append(context(e, "crit" if res == "crit" else "impact"))
	return out.filter(func(c: Dictionary) -> bool: return not c.is_empty())


## What a kind needs to be drawn for this event: the points on the map now, the colour, the art.
func context(e: Dictionary, kind: String) -> Dictionary:
	var row: Dictionary = lib.get("kinds", {}).get(kind, {})
	if row.is_empty() or str(row.get("group", "")) == "state":
		return {}
	var t := field.tile()
	var from := _point(str(e.get("by_at", e.get("to_at", e.get("at", "")))))
	var to := _point(str(e.get("to_at", e.get("at", e.get("by_at", "")))))
	if from == Vector2.INF or to == Vector2.INF:
		return {}
	if e.has("from"):  # a body moved: from where it stood
		from = _point(str(e["from"]))
	var cells: Array = []
	for tag: Variant in e.get("cells", []):
		cells.append(_point(str(tag)))
	var palette: Dictionary = lib.get("palette", {})
	var key := str(row.get("colour", e.get("dtype", "magic")))
	if kind in ["impact", "crit"]:
		key = str(e.get("dtype", "magic"))
	var dir := (to - from).normalized() if to != from else Vector2.RIGHT
	var perp := Vector2(-dir.y, dir.x)
	var spread := (float(absi(hash([e.get("n", 0), kind])) % 100) / 100.0 - 0.5) * t * 1.2  # cosmetic, not the game's dice
	var beside := to + dir * t * 1.3 + perp * spread if kind != "undershoot" else from.lerp(to, 0.7) + perp * spread
	return {"anim": kind, "phases": (row.get("phases", []) as Array).duplicate(true), "from": from, "to": to, "beside": beside, "cells": cells,
		"tile": t, "colour": Color(str(palette.get(key, palette.get("magic", "#b8a6ff")))), "n": maxi(1, int(e.get("darts", 1))),
		"result": str(e.get("result", "")) if kind != "sigil" else ("debuff" if str(e.get("dtype")) == "debuff" else "buff"),
		"sprite": str(e.get("sprite", "")), "proj": str(e.get("proj", "")), "speed": speed, "frames": _frames_of(row),
		"art": _art, "sprites": lib.get("sprites", {}), "projectiles": lib.get("projectiles", {}), "palette": palette, "scene": str(row.get("scene", ""))}


## The middle of a square on the map, INF when the event has none.
func _point(tag: String) -> Vector2:
	if tag.is_empty() or field == null:
		return Vector2.INF
	return field.cell_point(FightGrid.y_x(tag))


func _frames_of(row: Dictionary) -> SpriteFrames:
	var path := str(row.get("frames", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	if not _frames.has(path):
		_frames[path] = load(path)
	return _frames[path]


## The animation of a context: its kind's scene, else the stubs.
func make(c: Dictionary) -> FightAnim:
	var path := str(c.get("scene", ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		if not _scenes.has(path):
			_scenes[path] = load(path)
		var node := (_scenes[path] as PackedScene).instantiate()
		if node is FightAnim:
			return node
		node.queue_free()
	return StubAnim.new()


func _run() -> void:
	_busy = true
	while not _queue.is_empty() and is_inside_tree():
		var step: Array = _queue.pop_front()
		var fast := _queue.size() > 4  # a long queue plays quicker: the fight does not wait for it
		var left := [step.size()]
		var playing: Array[FightAnim] = []
		for c: Dictionary in step:
			if fast:
				c["speed"] = float(c["speed"]) * 0.5
			var a := make(c)
			add_child(a)
			playing.append(a)
			a.finished.connect(func() -> void: left[0] -= 1, CONNECT_ONE_SHOT)
			a.play(c)
		var waited := 0.0
		while left[0] > 0 and waited < 5.0 and is_inside_tree():  # a scene of the author's that never ends is let go
			waited += get_process_delta_time()
			await get_tree().process_frame
		for a: FightAnim in playing:
			if is_instance_valid(a):
				a.queue_free()
	_busy = false


func busy() -> bool:
	return _busy


## A still of one kind mid-way, for the playtest's screenshot: the stub of phase `phase` at `k`.
func hold(e: Dictionary, kind: String, phase: int, k: float) -> FightAnim:
	clear()
	var c := context(e, kind)
	if c.is_empty():
		return null
	var a := make(c)
	add_child(a)
	if a is StubAnim:
		(a as StubAnim).hold(c, phase, k)
	return a
