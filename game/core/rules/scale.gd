class_name Scale
extends RefCounted
## One scale (v0.7.60, ADR-0012): a value and its steps from the data. Friendship, standing, favor, ranks, ages and
## levels keep their own values and meanings; what they share is this lookup.


## The last step reached: `steps` rise by `key`. `fallback` — below the first one.
static func step(steps: Array, value: float, key: String = "at", fallback: Dictionary = {}) -> Dictionary:
	var out := fallback
	for st: Dictionary in steps:
		if value >= float(st[key]):
			out = st
	return out


## The index of the last step reached (0 — none yet): ranks and levels, a table of numbers or of steps.
static func index(steps: Array, value: float, key: String = "at") -> int:
	var out := 0
	for i in steps.size():
		if value >= (float(steps[i][key]) if steps[i] is Dictionary else float(steps[i])):
			out = i
	return out


## The value of the next step up, -1 at the top.
static func next(steps: Array, value: float, key: String = "at") -> int:
	for st: Dictionary in steps:
		if float(st[key]) > value:
			return int(st[key])
	return -1


## The deepest step passed going down: `steps` fall by `key` (hunger below a mark, a quarrel under zero).
static func below(steps: Array, value: float, key: String = "below", inclusive: bool = false) -> Dictionary:
	var out := {}
	for st: Dictionary in steps:
		if value < float(st[key]) or (inclusive and value == float(st[key])):
			out = st
	return out


## The last row reached of a table of [threshold, value…]; [] below the first.
static func row(rows: Array, value: float) -> Array:
	var out: Array = []
	for r: Array in rows:
		if value >= float(r[0]):
			out = r
	return out


## How many thresholds were passed, both ways: −3…+3 on a list of positive numbers.
static func signed(thresholds: Array, value: float) -> int:
	var out := 0
	for t: Variant in thresholds:
		if value >= float(t):
			out += 1
		elif value <= -float(t):
			out -= 1
	return out
