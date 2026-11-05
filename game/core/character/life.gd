class_name Life
extends RefCounted
## «Своя жизнь» of anybody (v0.8.4.20, ADR-0016): work, property, the bank, study, a shop and offices are parts of a
## character's own record — the hero's sheet or a person's record in `s.beings` — so a person may work, own a house, keep
## money in the bank and study by the hero's rules. What stays the hero's: what people think of the hero (attitude,
## memory, a settlement's fame, an organization's points), its crimes (v0.8.4.21) and the master's view.

## The parts of a record its own life keeps (declared in Being.PARTS).
const PARTS: Array[String] = ["jobs", "jobs_tried", "property", "bank", "study", "shop", "offices", "towns", "debts", "development",
	"skill_profs", "tools", "languages", "spells", "recipes", "stolen_animals"]


## The record holding the life of `who`: the hero's sheet, a person's record (never its fighter). With `data` a person's
## pockets are filled first, so what it earns or buys lands beside what it carries.
static func of(s: GameSession, who: String, data: Dictionary = {}) -> Dictionary:
	if who == Being.HERO:
		return s.character
	if not data.is_empty():
		Gear.of(s, data, who)
	return Being.of(s, who)


## Where `who` is now: the hero's room, a person's by its hours.
static func room(s: GameSession, data: Dictionary, who: String) -> String:
	return s.room_id if who == Being.HERO else Where.npc_room(s, data, who)


## Who keeps `part` of its own life, the hero first: the hooks of time run each one's day.
static func holders(s: GameSession, part: String) -> Array[String]:
	var out: Array[String] = [Being.HERO]
	for id: String in Being.with(s, part):
		if id != Being.HERO:
			out.append(id)
	return out


## The day of every holder of `part` through `run(s, data, who)`; the lines are the hero's, a person's day is quiet.
static func each(s: GameSession, data: Dictionary, part: String, run: Callable) -> Array[String]:
	var lines: Array[String] = []
	for who: String in holders(s, part):
		var got: Array[String] = run.call(s, data, who)
		if who == Being.HERO:
			lines = got
	return lines


## The mark of `who` as an owner of a place, a beast or a thing: the hero's, else its id.
## The NPC stands beside `who` now (v0.8.4.29.5, one place for a clerk, a banker, a teacher, an employer, a trader).
static func beside(s: GameSession, data: Dictionary, who: String, npc_id: String) -> bool:
	return s.npcs_here(data["world"], room(s, data, who)).has(npc_id)


static func owner(who: String) -> String:
	return OwnerRules.HERO if who == Being.HERO else who
