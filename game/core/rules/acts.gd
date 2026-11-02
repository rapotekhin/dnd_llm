class_name Acts
extends RefCounted
## Every act of a fight, read from core/acts/ by itself: there is no list to add a new one to (v0.8.4.7, ADR-0016). The buttons
## of the player and the choice of the AI both come from here.

const DIR := "res://core/acts/"

static var _all: Dictionary = {}


static func _load() -> Dictionary:
	if _all.is_empty():
		var names: Array = Array(ResourceLoader.list_directory(DIR))
		names.sort()
		for file: String in names:  # an exported game lists its scripts as .gdc too
			var at := file.get_basename()
			if file.get_extension() in ["gd", "gdc"] and at != "act" and not _all.has(at):
				var a: Act = load(DIR + at + ".gd").new()
				a.id = at
				_all[at] = a
	return _all


static func all() -> Array[Act]:
	var out: Array[Act] = []
	out.assign(_load().values())
	return out


static func one(id: String) -> Act:
	return _load()[id]


## What `f` has a button for on a tab.
static func on_tab(s: GameSession, data: Dictionary, f: Dictionary, tab: String) -> Array[Act]:
	return all().filter(func(a: Act) -> bool: return a.tab() == tab and a.shown(s, data, f))


## The acts it would take for nothing but points, best first: `action` true — those that cost the action, else the rest of
## `when`. Only what needs no aim and it can do now.
static func wanted(s: GameSession, data: Dictionary, f: Dictionary, action: bool, when: String = "") -> Array[Act]:
	var out: Array[Act] = []
	for a: Act in all():
		if not a.aim().is_empty() or a.worth(s, data, f) <= 0.0 or not a.can(s, data, f).is_empty():
			continue
		if (a.cost(s, data, f) == "action") == action and (action or a.when() == when):
			out.append(a)
	out.sort_custom(func(x: Act, y: Act) -> bool: return x.worth(s, data, f) > y.worth(s, data, f))
	return out
