class_name WorldEvent
extends RefCounted
## One way a deed reaches the world (v0.7.60.1, ADR-0012). A rule says what happened and gives its fact; who cares is
## this list, in its order: a system that wants to hear of a deed adds a line here, and no rule calls another's listener.

static var _listeners: Array[Dictionary] = []


## The listeners with the kinds they hear; `run` takes (s, data, fact) and may return lines.
static func registry() -> Array[Dictionary]:
	if _listeners.is_empty():
		_listeners = [
			{"id": "memory", "on": ["quest_done"], "run": _memory},
			{"id": "heir", "on": ["dying"], "run": _heir},  # before it is dead: the dead restock nothing
			{"id": "quests", "on": ["death"], "run": _quests},
			{"id": "faith", "on": ["deed"], "run": _faith},  # a vow and a commandment hear what the hero did (v0.7.49)
			{"id": "faction_crime", "on": ["crime_known"], "run": _faction_crime},
			{"id": "people", "on": ["crime_known"], "run": CrimeRules.people_know},
			{"id": "assault_bond", "on": ["crime_known"], "run": _assault_bond},
			{"id": "fame", "on": ["crime_known"], "run": CrimeRules.fame_known},  # the reputation and the news (v0.7.47)
			{"id": "wanted", "on": ["crime_known"], "run": CrimeRules.wanted_known},
			{"id": "reputation", "on": ["caught", "quest_done"], "run": _reputation},
			{"id": "bond", "on": ["caught", "quest_done"], "run": _bond},
			{"id": "faction_caught", "on": ["caught"], "run": _faction_crime},
			{"id": "faction_bond", "on": ["bond"], "run": _faction_bond},
			{"id": "standing", "on": ["standing", "quest_done"], "run": _standing},
			{"id": "news_death", "on": ["death"], "run": _news_death},
			{"id": "news_place", "on": ["place_made"], "run": _news_place},
		]
	return _listeners


## Tells the world of `kind`: every listener hears it, in the list's order. Lines.
static func emit(s: GameSession, data: Dictionary, kind: String, fact: Dictionary = {}) -> Array[String]:
	var lines: Array[String] = []
	for l: Dictionary in registry():
		if (l["on"] as Array).has(kind):
			var said: Variant = (l["run"] as Callable).call(s, data, fact)
			if said is Array:
				lines.append_array(said)
	return lines


## The hero did a thing a vow may forbid: `what` — a crime's kind, or `check:<skill>`.
static func deed(s: GameSession, data: Dictionary, what: String, room_id: String = "") -> Array[String]:
	return emit(s, data, "deed", {"deed": what, "room": room_id})


## A deed a faction counts by `rules.factions.sources`.
static func standing(s: GameSession, data: Dictionary, faction: String, source: String, why: String) -> Array[String]:
	return emit(s, data, "standing", {"faction": faction, "source": source, "why": why})


static func _memory(s: GameSession, _data: Dictionary, f: Dictionary) -> void:
	s.remember(str(f["giver"]), "герой выполнил задание «%s»" % f["title"])


static func _heir(s: GameSession, data: Dictionary, f: Dictionary) -> Array[String]:
	return TradeRules.on_death(s, data, str(f["npc"]))  # v0.7.17.2: the goods to the heir


static func _quests(s: GameSession, data: Dictionary, f: Dictionary) -> Array[String]:
	return QuestRules.on_death(s, data, str(f["npc"]))


static func _faith(s: GameSession, data: Dictionary, f: Dictionary) -> Array[String]:
	return FaithRules.deed(s, data, str(f["deed"]), str(f.get("room", "")))


static func _faction_crime(s: GameSession, data: Dictionary, f: Dictionary) -> Array[String]:
	return FactionRules.on_crime(s, data, str(f["victim"]), str(f["crime"]))


static func _assault_bond(s: GameSession, data: Dictionary, f: Dictionary) -> Array[String]:
	if str(f["crime"]) != "assault":
		return []
	return BondRules.on_deed(s, data, str(f["victim"]), "assault", "нападение")  # v0.7.31


static func _reputation(s: GameSession, data: Dictionary, f: Dictionary) -> Array[String]:
	return ReputationRules.add(s, data, str(f["location"]), int(ReputationRules.cfg(data)["points"].get(str(f["points"]), 0)), str(f["why"]))  # v0.7.17


static func _bond(s: GameSession, data: Dictionary, f: Dictionary) -> Array[String]:
	return BondRules.on_deed(s, data, str(f["npc"]), str(f["bond_deed"]), str(f["bond_why"]))  # v0.7.31


static func _faction_bond(s: GameSession, data: Dictionary, f: Dictionary) -> Array[String]:
	return FactionRules.on_bond(s, data, str(f["npc"]), int(f["delta"]))  # v0.7.50


static func _standing(s: GameSession, data: Dictionary, f: Dictionary) -> Array[String]:
	return FactionRules.on_source(s, data, str(f["faction"]), str(f["source"]), str(f["why"]))  # v0.7.50


static func _news_death(s: GameSession, data: Dictionary, f: Dictionary) -> void:
	if not bool(f["by_hero"]):
		RumorRules.on_death(s, data, str(f["npc"]), str(f["room"]))  # v0.7.47


static func _news_place(s: GameSession, data: Dictionary, f: Dictionary) -> void:
	RumorRules.on_place(s, data, str(f["room"]))  # v0.7.47: the neighbours talk of it
