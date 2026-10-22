class_name DifficultyRules
extends RefCounted
## Difficulty of a game (roadmap M5 «Сложность», first iteration v0.7.20.4): chosen for a new game, changed in the
## settings, kept in `session.settings.difficulty`. For now it only adds `check_bonus` (rules.json `difficulty`) to the
## hero's checks and saving throws, death saves included; attacks stay as they are.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["difficulty"]


## The levels in order: «trivial», «easy», «normal», «hard».
static func levels(data: Dictionary) -> Array:
	return (cfg(data)["levels"] as Dictionary).keys()


static func level(s: GameSession, data: Dictionary) -> String:
	var id := str(s.settings.get("difficulty", cfg(data)["default"])) if s != null else str(cfg(data)["default"])
	return id if (cfg(data)["levels"] as Dictionary).has(id) else str(cfg(data)["default"])


## What the difficulty adds to a check or save of the hero.
static func bonus(s: GameSession, data: Dictionary) -> int:
	return int(cfg(data)["levels"][level(s, data)]["check_bonus"])


## For the check card and the lines: «сложность «Лёгкая» +10» ("" when it adds nothing).
static func note(s: GameSession, data: Dictionary) -> String:
	var b := bonus(s, data)
	if b == 0:
		return ""
	return "сложность «%s» %+d" % [str(cfg(data)["levels"][level(s, data)]["name"]), b]
