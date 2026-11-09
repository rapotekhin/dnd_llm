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


## A reward made for the party (v0.8.4.42.2, the author): a quest's coins and experience and the master's treasure budget
## are those of the whole party the fights are made for — one hero in a game for four takes the four's.
static func reward(s: GameSession, data: Dictionary, base: int) -> int:
	return base * party(s, data)


## The party sizes to choose from: 1..party.max.
static func party_sizes(data: Dictionary) -> Array:
	return range(1, int(cfg(data).get("party", {"max": 1})["max"]) + 1)


## A fight's XP budget for one hero made the party's: the DMG thresholds add up over the characters.
static func budget(s: GameSession, data: Dictionary, one: int) -> int:
	return one * party(s, data)


## The ceiling of the master's own fights, reinforcements and made lairs: a hard fight of the hero's level for the party
## at most, by the DMG — below the deadly threshold (v0.8.4.42.8).
static func hard_cap(s: GameSession, data: Dictionary) -> int:
	return QuestGen.tier_band(s, data, "hard", int(s.character.get("level", 1))).y


## The DMG's multiplier for a fight of `count` foes against the game's party (v0.8.4.38): by `rules.difficulty.crowd`,
## a step up for a small party (one or two heroes), a step down for a large one.
static func crowd_mult(s: GameSession, data: Dictionary, count: int) -> float:
	var c: Dictionary = cfg(data)["crowd"]
	var from: Array = c["from"]
	var i := 0
	for k: int in from.size():
		if maxi(count, 1) >= int(from[k]):
			i = k
	var n := party(s, data)
	i += 1 if n < int(c["small_party"]) else (-1 if n >= int(c["large_party"]) else 0)
	if i < 0:
		return float(c["mult_below"])
	return float(c["mult_above"]) if i >= from.size() else float(c["mult"][i])


## A fight weighed by the DMG: the foes' XP times the multiplier of their number. `foes` — [{xp, count}], the XP of one.
static func weigh(s: GameSession, data: Dictionary, foes: Array) -> int:
	return int(round(_raw(foes) * crowd_mult(s, data, _count(foes))))


static func _raw(foes: Array) -> int:
	var raw := 0
	for f: Dictionary in foes:
		raw += int(f["xp"]) * int(f.get("count", 1))
	return raw


static func _count(foes: Array) -> int:
	var count := 0
	for f: Dictionary in foes:
		count += int(f.get("count", 1))
	return count


## [{xp, count}] of SRD foes [{monster, count}].
static func of_monsters(data: Dictionary, foes: Array) -> Array:
	return foes.map(func(f: Dictionary) -> Dictionary: return {"xp": int(data["monsters"][str(f["monster"])]["xp"]), "count": int(f.get("count", 1))})


## For a refusal: «200 опыта ×2,5 за 4 врагов = 500».
static func weigh_text(s: GameSession, data: Dictionary, foes: Array) -> String:
	var count := _count(foes)
	return "%d опыта ×%s за %d %s = %d" % [_raw(foes), _mult_text(crowd_mult(s, data, count)), count, "врага" if count == 1 else "врагов",
		weigh(s, data, foes)]


static func _mult_text(m: float) -> String:
	return (str(int(m)) if is_equal_approx(m, round(m)) else str(m)).replace(".", ",")


## The multipliers for the master's frame: «1 — ×1,5; 2 — ×2; 3–6 — ×2,5; …».
static func crowd_line(s: GameSession, data: Dictionary) -> String:
	var from: Array = cfg(data)["crowd"]["from"]
	var parts: Array[String] = []
	for k: int in from.size():
		var a := int(from[k])
		var b := int(from[k + 1]) - 1 if k + 1 < from.size() else -1
		var span := str(a) if a == b else ("%d–%d" % [a, b] if b > 0 else "%d+" % a)
		parts.append("%s — ×%s" % [span, _mult_text(crowd_mult(s, data, a))])
	return "; ".join(parts)


## For the check card and the lines: «сложность «Лёгкая» +10» ("" when it adds nothing).
static func note(s: GameSession, data: Dictionary) -> String:
	var b := bonus(s, data)
	if b == 0:
		return ""
	return "сложность «%s» %+d" % [str(cfg(data)["levels"][level(s, data)]["name"]), b]
