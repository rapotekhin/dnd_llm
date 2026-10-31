class_name Cond
extends RefCounted
## One language of conditions (v0.7.68): a quest step's `when` and `needs`, a way's `when`, a room's and a trader's
## variant `when`, a row of `requires` (Require) are all read here. One fact: `encounter` (with `defeat` — a fight won, not
## slipped past), `secret` "room:id", `room` (been there), `arrive` (there now), `flag`, `not_flag`, `quest` (taken),
## `quest_done`; `all` / `any` of facts. `item` with `qty` — the hero carries it, beside the fact.
## `talk` and `choice` are closed by a button, never by facts (QuestRules).


static func met(s: GameSession, when: Dictionary) -> bool:
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
		return (when["all"] as Array).all(func(w: Dictionary) -> bool: return met(s, w))
	if when.has("any"):
		return (when["any"] as Array).any(func(w: Dictionary) -> bool: return met(s, w))
	return false


## A record that stands on a condition: no `when` — always.
static func holds(s: GameSession, record: Dictionary) -> bool:
	return not record.has("when") or met(s, record["when"])
