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


## How many heroes the master's fights are made for (v0.8.4.37): 1..party.max, kept in `session.settings.party`.
static func party(s: GameSession, data: Dictionary) -> int:
	var p: Dictionary = cfg(data).get("party", {"default": 1, "max": 1})
	var n := int(s.settings.get("party", p["default"])) if s != null else int(p["default"])
	return clampi(n, 1, int(p["max"]))


## The party sizes to choose from: 1..party.max.
static func party_sizes(data: Dictionary) -> Array:
	return range(1, int(cfg(data).get("party", {"max": 1})["max"]) + 1)


## A fight's XP budget for one hero made the party's: the DMG thresholds add up over the characters.
static func budget(s: GameSession, data: Dictionary, one: int) -> int:
	return one * party(s, data)


## The ceiling of the master's own fights and reinforcements: the hard fight of the hero's level for the party.
static func hard_cap(s: GameSession, data: Dictionary) -> int:
	return budget(s, data, int(CombatRules.cfg(data)["xp_budget_hard"].get(str(int(s.character.get("level", 1))), 750)))


## For the check card and the lines: «сложность «Лёгкая» +10» ("" when it adds nothing).
static func note(s: GameSession, data: Dictionary) -> String:
	var b := bonus(s, data)
	if b == 0:
		return ""
	return "сложность «%s» %+d" % [str(cfg(data)["levels"][level(s, data)]["name"]), b]
