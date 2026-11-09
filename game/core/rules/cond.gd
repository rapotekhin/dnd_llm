class_name Cond
extends RefCounted
## One language of conditions (v0.7.68): a quest step's `when` and `needs`, a way's `when`, a room's and a trader's
## variant `when`, a row of `requires` (Require) are all read here. One fact: `encounter` (with `defeat` — a fight won, not
## slipped past), `secret` "room:id", `room` (been there), `arrive` (there now), `flag`, `not_flag`, `quest` (taken),
## `quest_done`; `all` / `any` of facts. `item` with `qty` — the hero carries it, beside the fact. `has` — the hero carries
## this thing: enough by itself, whatever the fact beside it (a quest's find closed by the thing got another way, v0.8.4.42.1). Facts of the place, read
## with `data` (v0.8.4.27.4): `terrain` — the location's terrain is one of these, `weather` — today's weather here under the
## open sky is one of these (WeatherRules.here).
## `talk` and `choice` are closed by a button, never by facts (QuestRules).


static func met(s: GameSession, when: Dictionary, data: Dictionary = {}) -> bool:
	if when.has("terrain") or when.has("weather"):
		if data.is_empty():
			return false
		if when.has("terrain"):
			var w := WorldView.new(data["world"])
			return (when["terrain"] as Array).has(str(w.location(w.location_id(s.room_id)).get("terrain", "")))
		return (when["weather"] as Array).has(WeatherRules.here(s, data))
	if when.has("has") and int(s.character.get("inventory", {}).get(str(when["has"]), 0)) > 0:
		return true
	if when.has("item") and not when.has("talk") and int(s.character.get("inventory", {}).get(str(when["item"]), 0)) < int(when.get("qty", 1)):
		return false  # a thing left at a place (v0.7.34.5): the hero has to bring it
	if when.has("encounter"):
		return s.encounters_done.has(str(when["encounter"])) or (not bool(when.get("defeat", false)) and s.encounters_passed.has(str(when["encounter"])))
	if when.has("secret"):
		return Knows.has(s, Knows.SECRET, str(when["secret"]))
	if when.has("room"):
		return s.visited.has(str(when["room"]))
	if when.has("arrive"):  # the master's quests (v0.7.34.4): the hero is there now, whatever was before
		return s.room_id == str(when["arrive"])
	if when.has("flag"):
		return s.flags.has(str(when["flag"]))
	if when.has("not_flag"):  # v0.7.46: a ford open while it is not flooded
		return not s.flags.has(str(when["not_flag"]))
	if when.has("quest"):
		return s.quests_active.has(str(when["quest"]))
	if when.has("quest_done"):
		return s.quests_done.has(str(when["quest_done"]))
	if when.has("all"):
		return (when["all"] as Array).all(func(w: Dictionary) -> bool: return met(s, w, data))
	if when.has("any"):
		return (when["any"] as Array).any(func(w: Dictionary) -> bool: return met(s, w, data))
	return false


## A record that stands on a condition: no `when` — always.
static func holds(s: GameSession, record: Dictionary, data: Dictionary = {}) -> bool:
	return not record.has("when") or met(s, record["when"], data)
